# frozen_string_literal: true

module SpreeNotificationProviders
  module Importers
    # Fills provider inputs for one store without ever overwriting a value
    # that is already set, and keeps a printable report of what it did.
    class Writer
      Line = Struct.new(:key, :status, :detail, keyword_init: true) do
        def to_s
          "  #{key.ljust(28, '.')} #{[status, detail].compact.join(' ')}"
        end
      end

      attr_reader :store, :lines

      def initialize(store, dry_run: false)
        @store = store
        @dry_run = dry_run
        @lines = []
        @configs = {}
        @entries = {}
        @sources = Hash.new { |hash, key| hash[key] = Set.new }
      end

      def dry_run? = @dry_run

      # scope is :shared or a channel.
      def set_input(provider_key, scope, name, value, source:, flag: nil)
        value = value.to_s.strip
        return if value.empty?

        definition = SpreeNotificationProviders.provider(provider_key) or return
        inputs = scope == :shared ? definition.shared_inputs : Array(definition.capability(scope)&.inputs)
        input = inputs.find { |candidate| candidate.name == name.to_sym } or return

        record = scope == :shared ? config(provider_key) : entry(provider_key, scope)
        key = "#{provider_key}.#{scope == :shared ? '' : "#{scope}."}#{name}"
        if record.raw_value(input).present?
          lines << Line.new(key: key, status: 'unchanged')
          return
        end

        record.write_raw(input, value)
        @sources[provider_key.to_sym] << source_kind(source)
        detail = input.secret? ? "(secret, #{mask(value)})" : nil
        lines << Line.new(key: key, status: "imported from #{source}", detail: [detail, flag].compact.join(' ').presence)
      end

      def set_template(provider_key, channel, message_type, value, source:)
        value = value.to_s.strip
        return if value.empty?

        record = entry(provider_key, channel)
        key = "#{provider_key}.#{channel}.template.#{message_type}"
        if record.templates.to_h[message_type.to_s].present?
          lines << Line.new(key: key, status: 'unchanged')
          return
        end

        record.templates = record.templates.to_h.merge(message_type.to_s => value)
        @sources[provider_key.to_sym] << source_kind(source)
        lines << Line.new(key: key, status: "imported from #{source}")
      end

      # Creates the channel entry if missing. Existing entries keep their
      # enabled flag and position.
      def ensure_entry(provider_key, channel, enabled:)
        record = entry(provider_key, channel)
        record.enabled = enabled if record.new_record?
        record
      end

      def note(key, text)
        lines << Line.new(key: key, status: text)
      end

      def touched?(provider_key)
        @sources.key?(provider_key.to_sym)
      end

      def save!
        return if dry_run?

        ActiveRecord::Base.transaction do
          @configs.each do |provider_key, record|
            next unless record.new_record? || record.changed?

            if @sources.key?(provider_key)
              kinds = @sources[provider_key]
              record.import_source ||= kinds.size > 1 ? 'mixed' : kinds.first
              record.imported_at ||= Time.current
            end
            record.save!(validate: false)
          end
          @entries.each_value do |record|
            next unless record.new_record? || record.changed?

            record.provider_config # make sure the shared config exists
            record.save!(validate: false)
          end
        end
      end

      def report
        (["store #{store.code}"] + lines.map(&:to_s)).join("\n")
      end

      private

      def config(provider_key)
        @configs[provider_key.to_sym] ||=
          Spree::NotificationProviderConfig.find_or_initialize_by(store_id: store.id, provider_key: provider_key.to_s)
      end

      def entry(provider_key, channel)
        @entries[[provider_key.to_sym, channel.to_sym]] ||= begin
          config(provider_key)
          Spree::NotificationChannelProvider.find_or_initialize_by(store_id: store.id, channel: channel.to_s,
                                                                   provider_key: provider_key.to_s)
        end
      end

      def source_kind(source)
        source.to_s.start_with?('ENV') ? 'env' : 'legacy_columns'
      end

      def mask(value)
        value.length >= 12 ? "••••#{value[-4..]}" : 'set'
      end
    end
  end
end
