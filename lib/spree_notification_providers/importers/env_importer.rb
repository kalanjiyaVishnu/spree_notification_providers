# frozen_string_literal: true

require 'spree_notification_providers/importers/writer'

module SpreeNotificationProviders
  module Importers
    # Copies the environment variables named by each provider input's `env:`
    # into one store's configuration. Fills blanks only; safe to rerun.
    # A provider with any value found gets an enabled entry on each of its
    # channels (an entry missing inputs or templates simply shows as not ready).
    #
    #   bin/rails g spree_notification_providers:import_env --store=<code>
    class EnvImporter
      def initialize(store, env: ENV, dry_run: false)
        @env = env
        @writer = Writer.new(store, dry_run: dry_run)
      end

      def call
        SpreeNotificationProviders.providers.each do |definition|
          shared_found = import_inputs(definition, :shared, definition.shared_inputs)
          definition.channels.each do |channel, capability|
            channel_found = import_inputs(definition, channel, capability.inputs)
            @writer.ensure_entry(definition.key, channel, enabled: true) if shared_found || channel_found
          end
        end
        @writer.save!
        @writer
      end

      private

      # @return [Boolean] whether any input had a value in the environment
      def import_inputs(definition, scope, inputs)
        inputs.map do |input|
          value = input.env.present? ? @env[input.env].to_s.strip.presence : nil
          @writer.set_input(definition.key, scope, input.name, value, source: "ENV #{input.env}") if value
          value.present?
        end.any?
      end
    end
  end
end
