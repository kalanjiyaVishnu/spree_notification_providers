# frozen_string_literal: true

module SpreeNotificationProviders
  module Adapters
    # WhatsApp template messages through Gupshup (https://gupshup.io).
    #
    # The send endpoint takes the template UUID. A template configured by name
    # is resolved through the app's template list (needs the app ID) and cached.
    # A "submitted" reply only means Gupshup accepted the message; delivery
    # failures arrive later on the webhook (Spree::Webhooks::GupshupController).
    class Gupshup < Base
      HOST = 'https://api.gupshup.io'
      SEND_PATH = '/wa/api/v1/template/msg'
      TEMPLATE_CACHE_TTL = 12.hours
      UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

      def self.template_cache_key(store)
        "notification_providers:gupshup_template:#{store.id}"
      end

      def self.clear_template_cache(store)
        Rails.cache.delete(template_cache_key(store))
      end

      def deliver(message, context)
        template_id = begin
          resolve_template_id(context)
        rescue StandardError => e
          # Nothing has been sent yet, so any lookup error is a definite failure.
          return Result.failed("template_lookup_failed: #{HttpOutcome.from_error(e).reason}")
        end
        return Result.failed('template_not_found') if template_id.blank?

        params = message.kind == :otp ? [message.code.to_s] : Array(message.variables.to_h.values).map(&:to_s)
        response = Http.request(
          :post, "#{HOST}#{SEND_PATH}",
          headers: { 'apikey' => context[:api_key].to_s },
          form: {
            'channel' => 'whatsapp',
            'source' => context[:source_number],
            'destination' => message.to.gsub(/\D/, ''),
            'src.name' => context[:app_name],
            'template' => { id: template_id, params: params }.to_json
          }
        )
        body = Http.parse_json(response.body)
        accepted = body['status'] == 'submitted'
        provider_message = accepted ? nil : scrub("status #{body['status'].presence || 'unknown'}", context)
        HttpOutcome.from_response(response, body, accepted: accepted, message_id: body['messageId'],
                                                  provider_message: provider_message)
      rescue StandardError => e
        HttpOutcome.from_error(e)
      end

      private

      def resolve_template_id(context)
        template = context.template.to_s.strip
        return template if template.match?(UUID_FORMAT)
        return nil if template.blank? || context[:app_id].blank?

        cache_key = self.class.template_cache_key(context.store)
        cached = Rails.cache.read(cache_key)
        return cached[:id] if cached.is_a?(Hash) && cached[:name] == template && cached[:app_id] == context[:app_id]

        id = lookup_template_id(template, context)
        if id
          Rails.cache.write(cache_key, { name: template, app_id: context[:app_id], id: id },
                            expires_in: TEMPLATE_CACHE_TTL)
        end
        id
      end

      def lookup_template_id(name, context)
        response = Http.request(
          :get, "#{HOST}/wa/app/#{ERB::Util.url_encode(context[:app_id])}/template",
          headers: { 'apikey' => context[:api_key].to_s }, query: { templateStatus: 'APPROVED' }
        )
        return nil unless response.code.to_i.between?(200, 299)

        templates = Array(Http.parse_json(response.body)['templates'])
        match = templates.find { |t| t['elementName'] == name && t['status'].to_s.casecmp('APPROVED').zero? }
        match&.dig('id')
      end
    end
  end
end
