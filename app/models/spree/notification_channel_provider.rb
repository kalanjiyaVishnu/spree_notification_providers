# frozen_string_literal: true

module Spree
  # A store's use of one provider on one channel: on/off, priority position,
  # channel inputs and templates per message type.
  class NotificationChannelProvider < Spree::Base
    include Spree::NotificationProviderSettings

    has_prefix_id :nchp

    CHANNELS = %w[email sms whatsapp].freeze
    STATUSES = %i[ready not_ready disabled unavailable].freeze

    belongs_to :store, class_name: 'Spree::Store'

    acts_as_list scope: %i[store_id channel], add_new_at: :bottom

    validates :channel, inclusion: { in: CHANNELS }
    validates :provider_key, presence: true, uniqueness: { scope: %i[store_id channel] }
    validate :provider_supports_channel
    validate { validate_inputs(channel_inputs) if capability }
    validate :templates_valid

    scope :enabled, -> { where(enabled: true) }
    scope :for_channel, ->(channel) { where(channel: channel.to_s).order(:position) }

    # Registry -------------------------------------------------------------

    def definition
      SpreeNotificationProviders.provider(provider_key)
    end

    def capability
      definition&.capability(channel)
    end

    def channel_inputs
      capability&.inputs || []
    end

    def shared_inputs
      definition&.shared_inputs || []
    end

    def provider_config
      @provider_config ||= Spree::NotificationProviderConfig.find_or_create_by!(store_id: store_id,
                                                                               provider_key: provider_key)
    end

    def provider_config=(config)
      @provider_config = config
    end

    def template_capable?
      capability.present? && (capability.template_required? || capability.supports_kind?(:template) ||
        capability.supports_kind?(:otp))
    end

    # Values ---------------------------------------------------------------

    # Shared + channel inputs, secrets decrypted, defaults applied.
    def values
      config = provider_config
      shared = shared_inputs.to_h { |input| [input.name, input.resolve(config.raw_value(input))] }
      own = channel_inputs.to_h { |input| [input.name, input.resolve(raw_value(input))] }
      shared.merge(own)
    end

    def template_for(message_type, message = nil)
      message&.template_override(provider_key).presence || templates.to_h[message_type.to_s].presence
    end

    # Used by "Send test": the test template if set, else any configured one.
    def test_template
      templates.to_h['provider_test'].presence || templates.to_h.values.find(&:present?)
    end

    def context(template: nil)
      SpreeNotificationProviders::Adapters::Context.new(
        store: store, channel: channel.to_sym, settings: values, template: template,
        templates: templates.to_h
      )
    end

    # Readiness ------------------------------------------------------------

    def missing_inputs
      return [] unless definition

      config = provider_config
      missing = shared_inputs.select { |i| i.required? && i.resolve(config.raw_value(i)).blank? }.map(&:label)
      missing += channel_inputs.select { |i| i.required? && i.resolve(raw_value(i)).blank? }.map(&:label)
      missing += capability.extra_missing(values, templates.to_h) if capability
      missing.uniq
    end

    def ready?
      enabled? && definition.present? && capability.present? && missing_inputs.empty?
    end

    def ready_for?(message_type, message = nil)
      ready? && skip_reason_for(message, message_type: message_type).nil?
    end

    # Why the router would skip this entry for the message, or nil.
    def skip_reason_for(message, message_type: nil)
      return 'unavailable' if definition.nil? || capability.nil?

      missing = missing_inputs
      return "not_ready: missing #{missing.join(', ')}" if missing.any?

      kind = effective_kind(message)
      return 'unsupported' if kind && !capability.supports_kind?(kind)

      type = message&.type || message_type
      return 'no_template' if capability.template_required? && template_for(type, message).blank?

      nil
    end

    # An HTML email that names this provider's template is sent as that
    # template (e.g. an email template with a MSG91 template id).
    def effective_kind(message)
      kind = message&.kind
      if kind == :html && message.template_override(provider_key).present? && capability&.supports_kind?(:template)
        :template
      else
        kind
      end
    end

    def status
      return :unavailable if definition.nil? || capability.nil?
      return :disabled unless enabled?

      missing_inputs.empty? ? :ready : :not_ready
    end

    # Used by: the channels whose entries share this provider's config.
    def shared_with_channels
      Spree::NotificationChannelProvider.where(store_id: store_id, provider_key: provider_key)
                                        .order(:channel).pluck(:channel)
    end

    private

    def provider_supports_channel
      if definition.nil?
        errors.add(:provider_key, 'is not a registered provider')
      elsif !definition.supports?(channel)
        errors.add(:channel, "is not supported by #{definition.label}")
      end
    end

    def templates_valid
      return unless capability&.template_format

      templates.to_h.each do |type, value|
        next if value.blank? || capability.template_valid?(value)

        errors.add(:base, "Template for #{type} is not in the expected format")
      end
    end
  end
end
