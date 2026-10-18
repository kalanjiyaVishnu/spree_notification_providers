# frozen_string_literal: true

module SpreeNotificationProviders
  module Adapters
    # Writes the message to the Rails log instead of sending it. Registered
    # only when `config.enable_log_provider` is true (non-production default).
    class Log < Base
      def deliver(message, context)
        Rails.logger.info(
          "[NotificationProviders::Log] store=#{context.store&.id} channel=#{message.channel} " \
          "type=#{message.type} kind=#{message.kind} to=#{message.to}" \
          "#{" code=#{message.code}" if message.code}#{" subject=#{message.subject.inspect}" if message.subject}"
        )
        Result.delivered("sim-#{SecureRandom.hex(8)}")
      end

      def deliver_bulk(bulk, context)
        Rails.logger.info(
          "[NotificationProviders::Log] store=#{context.store&.id} channel=#{bulk.channel} type=#{bulk.type} " \
          "bulk recipients=#{bulk.recipients.size}"
        )
        Result.delivered("sim-#{SecureRandom.hex(8)}")
      end
    end
  end
end
