# frozen_string_literal: true

module SpreeNotificationProviders
  module Adapters
    # MSG91 (https://msg91.com):
    #   email    - Email API, provider-side template + variables
    #   sms      - OTP API for codes, Flow API for templates (DLT-approved)
    #   whatsapp - OTP API with whatsapp=1
    class Msg91 < Base
      OTP_URL = 'https://control.msg91.com/api/v5/otp'
      FLOW_URL = 'https://control.msg91.com/api/v5/flow'
      EMAIL_URL = 'https://control.msg91.com/api/v5/email/send'

      def deliver(message, context)
        case message.channel
        when :email then send_email(message.to, message.to_name, message, context)
        when :sms then message.kind == :otp ? send_otp(message, context) : send_flow([message.to], message, context)
        when :whatsapp then send_otp(message, context, whatsapp: true)
        end
      rescue StandardError => e
        HttpOutcome.from_error(e)
      end

      def deliver_bulk(bulk, context)
        case bulk.channel
        when :email then send_email_batch(bulk.recipients, bulk, context)
        when :sms then send_flow(bulk.recipients, bulk, context)
        else Result.failed('unsupported')
        end
      rescue StandardError => e
        HttpOutcome.from_error(e)
      end

      private

      def send_otp(message, context, whatsapp: false)
        query = {
          template_id: context.template,
          mobile: international(message.to, context),
          otp: message.code,
          otp_expiry: message.expiry_minutes || 10
        }
        query[:sender] = context[:sender_id] if !whatsapp && context[:sender_id].present?
        query[:whatsapp] = 1 if whatsapp

        response = Http.request(:post, OTP_URL, headers: auth(context), query: query)
        body = Http.parse_json(response.body)
        accepted = body['type'] == 'success' || body['message_id'].present?
        outcome(response, body, accepted, body['message_id'] || body['request_id'], context)
      end

      def send_flow(phones, message, context)
        variables = message.variables.to_h.stringify_keys
        payload = {
          template_id: context.template,
          short_url: '1',
          recipients: phones.map { |phone| { 'mobiles' => international(phone, context) }.merge(variables) }
        }
        response = Http.request(:post, FLOW_URL, headers: auth(context), json: payload)
        body = Http.parse_json(response.body)
        # A successful Flow reply carries the request id in "message".
        message_id = body['type'] == 'success' ? body['message'] : body['request_id']
        outcome(response, body, body['type'] != 'error', message_id, context)
      end

      def send_email(to, to_name, message, context)
        send_email_payload([{ to: [{ email: to, name: to_name.presence || to }.compact], variables: message.variables }],
                           message, context)
      end

      def send_email_batch(emails, bulk, context)
        send_email_payload(emails.map { |email| { to: [{ email: email }], variables: bulk.variables } }, bulk, context)
      end

      def send_email_payload(recipients, message, context)
        from_email = message.from_email || context[:default_from_email]
        payload = {
          recipients: recipients,
          from: { name: message.from_name || context.store&.name, email: from_email }.compact,
          domain: context[:domain].presence || from_email.to_s.split('@').last,
          template_id: context.template
        }
        reply_to = message.respond_to?(:reply_to) ? message.reply_to : nil
        payload[:reply_to] = [{ email: reply_to }] if reply_to.present?

        response = Http.request(:post, EMAIL_URL, headers: auth(context), json: payload)
        body = Http.parse_json(response.body)
        accepted = body['hasError'] != true && body['status'] != 'fail'
        outcome(response, body, accepted, body.dig('data', 'unique_id') || body['request_id'], context)
      end

      def outcome(response, body, accepted, message_id, context)
        provider_message = scrub(body['message'].presence || body['errors'].to_s.presence, context)
        HttpOutcome.from_response(response, body, accepted: accepted, message_id: message_id,
                                                  provider_message: provider_message)
      end

      def auth(context)
        { 'authkey' => context[:auth_key].to_s, 'accept' => 'application/json' }
      end

      # MSG91 wants country-code-prefixed numbers; a national 10-digit number
      # gets the channel's default country code.
      def international(phone, context)
        digits = phone.to_s.gsub(/\D/, '')
        digits.length == 10 ? "#{context[:default_country_code].presence || '91'}#{digits}" : digits
      end
    end
  end
end
