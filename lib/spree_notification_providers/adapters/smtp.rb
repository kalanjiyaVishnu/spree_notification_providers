# frozen_string_literal: true

require 'mail'
require 'net/smtp'

module SpreeNotificationProviders
  module Adapters
    # Sends rendered email over the store's own SMTP account. Never touches
    # the global Action Mailer configuration.
    class Smtp < Base
      DEFINITE_SMTP_ERRORS = {
        'Net::SMTPAuthenticationError' => 'smtp_auth',
        'Net::SMTPFatalError' => 'smtp_rejected',
        'Net::SMTPServerBusy' => 'smtp_busy',
        'Net::SMTPSyntaxError' => 'smtp_syntax',
        'Net::SMTPUnknownError' => 'smtp_unknown_reply'
      }.freeze

      def deliver(message, context)
        mail = build_mail(message, context)
        mail.delivery_method(:smtp, smtp_settings(context))
        mail.deliver!
        Result.delivered(mail.message_id)
      rescue StandardError => e
        classify(e, context)
      end

      private

      def build_mail(message, context)
        mail = message.mail ? message.mail.dup : Mail.new
        unless message.mail
          mail.to = message.to
          mail.subject = message.subject
          mail.html_part = Mail::Part.new do
            content_type 'text/html; charset=UTF-8'
            body message.html.to_s
          end
        end

        if message.from_email
          mail.from = message.from_name ? "#{message.from_name} <#{message.from_email}>" : message.from_email
        elsif mail.from.blank?
          mail.from = context[:from_address]
        end
        mail.reply_to = message.reply_to if message.reply_to
        mail
      end

      def smtp_settings(context)
        {
          address: context[:host],
          port: context[:port],
          user_name: context[:username],
          password: context[:password],
          authentication: context[:authentication].presence&.to_sym || :plain,
          enable_starttls_auto: context[:starttls] != false,
          open_timeout: SpreeNotificationProviders.configuration.http_timeout_seconds,
          read_timeout: SpreeNotificationProviders.configuration.http_timeout_seconds
        }
      end

      def classify(error, context)
        code = DEFINITE_SMTP_ERRORS[error.class.name]
        return Result.failed([code, scrub(error.message, context)].compact.join(': ')) if code

        HttpOutcome.from_error(error)
      end
    end
  end
end
