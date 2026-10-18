# frozen_string_literal: true

module SpreeNotificationProviders
  module Adapters
    # What an adapter gets for each call.
    #
    # settings  - the provider's shared and channel inputs merged, secrets
    #             decrypted, defaults applied, keyed by Symbol
    # template  - the template for this message's type (or the message's own
    #             override), or nil
    # templates - every template configured on the channel, keyed by type
    Context = Struct.new(:store, :channel, :settings, :template, :templates, keyword_init: true) do
      def [](name)
        settings[name.to_sym]
      end
    end

    # Subclass this to add a provider. Return a Result from every method;
    # handle transport errors yourself (see HttpOutcome). An exception raised
    # here is recorded as a failure by the router.
    class Base
      TEST_CODE = '123456'

      attr_reader :definition

      def initialize(definition)
        @definition = definition
      end

      def deliver(_message, _context)
        raise NotImplementedError, "#{self.class.name}#deliver must be implemented"
      end

      def deliver_bulk(_bulk, _context)
        raise NotImplementedError, "#{self.class.name}#deliver_bulk must be implemented"
      end

      # Admin "Send test": a real send through this provider only.
      def test_message(channel, to, context)
        deliver(test_message_for(channel, to), context)
      end

      def test_message_for(channel, to)
        capability = definition.capability(channel)
        kind = if capability.supports_kind?(:otp) then :otp
               elsif capability.supports_kind?(:html) then :html
               else :template
               end
        Message.new(
          channel: channel, type: :provider_test, kind: kind, to: to,
          code: TEST_CODE, expiry_minutes: 10,
          subject: I18n.t('spree_notification_providers.test_message.subject', default: 'Test message'),
          html: I18n.t('spree_notification_providers.test_message.html',
                       default: '<p>This is a test message from your store.</p>'),
          variables: {}
        )
      end

      protected

      # Replaces any secret input value found in `text` before it is stored as
      # a reason or logged.
      def scrub(text, context)
        return nil if text.blank?

        secrets = definition_secret_keys(context.channel).filter_map { |key| context[key].presence&.to_s }
        secrets.reduce(text.to_s) { |memo, secret| memo.gsub(secret, '[FILTERED]') }.truncate(120)
      end

      def definition_secret_keys(channel)
        inputs = definition.shared_inputs + Array(definition.capability(channel)&.inputs)
        inputs.select(&:secret?).map(&:name)
      end
    end
  end
end
