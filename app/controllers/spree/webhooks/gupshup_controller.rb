# frozen_string_literal: true

module Spree
  module Webhooks
    # Receives Gupshup message events. Gupshup only learns that a number isn't
    # on WhatsApp after accepting the send, so a "failed" event marks the
    # delivery failed and publishes `notification.delivery_failed` (which, for
    # login codes, triggers the email backup).
    #
    # Callbacks are unsigned; the URL carries the store's Gupshup webhook
    # secret (Notification providers → Gupshup → Webhook secret), filtered
    # from logs:
    #   POST /webhooks/gupshup?secret=<webhook secret>
    #
    # The secret is checked against the store that owns the message, found
    # from its delivery row or, for messages sent before this gem, through a
    # registered message resolver.
    class GupshupController < ActionController::API
      def create
        event = request.request_parameters.presence || parse_body
        return head(:ok) unless failure_event?(event)

        message_ids = [event.dig('payload', 'gsId'), event.dig('payload', 'id')].compact_blank
        delivery = Spree::NotificationDelivery.where(provider_key: 'gupshup', provider_message_id: message_ids).first
        store = delivery&.store || message_ids.lazy.filter_map do |id|
          SpreeNotificationProviders.resolve_message_store(:gupshup, id)
        end.first
        return head(:not_found) unless store && secret_matches?(store)

        reason = event.dig('payload', 'payload', 'reason').to_s.truncate(120)
        delivery&.mark_failed!(reason)
        Spree::Events.publish('notification.delivery_failed', {
                                'store_id' => store.id, 'delivery_id' => delivery&.id,
                                'provider_message_id' => delivery&.provider_message_id || message_ids.first,
                                'reason' => reason
                              })
        head :ok
      end

      private

      def failure_event?(event)
        event.is_a?(Hash) && event['type'] == 'message-event' &&
          event['payload'].is_a?(Hash) && event['payload']['type'] == 'failed'
      end

      def secret_matches?(store)
        entry = Spree::NotificationProviderConfig.find_by(store_id: store.id, provider_key: 'gupshup')
        input = SpreeNotificationProviders.provider(:gupshup)&.shared_inputs&.find { |i| i.name == :webhook_secret }
        expected = entry && input ? entry.raw_value(input).to_s : ''
        expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, params[:secret].to_s)
      end

      def parse_body
        JSON.parse(request.raw_post.presence || '{}')
      rescue JSON::ParserError
        nil
      end
    end
  end
end
