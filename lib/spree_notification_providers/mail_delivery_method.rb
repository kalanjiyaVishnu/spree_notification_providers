# frozen_string_literal: true

module SpreeNotificationProviders
  # Action Mailer delivery method that sends every mail through the store's
  # Email providers in priority order.
  #
  #   config.action_mailer.delivery_method = :spree_notification_providers
  #
  # Headers read, then removed before sending:
  #   X-Spree-Store-Id                 - store id (else Spree::Current.store, else default store)
  #   X-Spree-Message-Type             - registered message type (default: transactional_email)
  #   X-Spree-Provider-Template-<key>  - template override for one provider, e.g. ...-Msg91
  #
  # Raises DeliveryFailed only when no provider can have taken the mail, so
  # deliver_later retries. An :unknown outcome is not retried: the mail may
  # already be on its way.
  class MailDeliveryMethod
    STORE_HEADER = 'X-Spree-Store-Id'
    TYPE_HEADER = 'X-Spree-Message-Type'
    TEMPLATE_HEADER_PREFIX = 'X-Spree-Provider-Template-'

    attr_accessor :settings

    def initialize(settings = {})
      @settings = settings
    end

    def deliver!(mail)
      store = resolve_store(header(mail, STORE_HEADER))
      type = header(mail, TYPE_HEADER).presence || 'transactional_email'
      templates = template_headers(mail)
      strip_headers(mail)

      message = Message.new(channel: :email, type: type, kind: :html, to: Array(mail.to).join(', '),
                            subject: mail.subject, mail: mail, templates: templates)
      result = SpreeNotificationProviders.deliver(store: store, message: message)

      if result.retryable?
        raise DeliveryFailed, "no email provider delivered #{type} (#{result.reasons.join('; ').presence || 'no provider'})"
      end

      if result.outcome == :unknown
        Rails.logger.warn("[NotificationProviders] mail outcome unknown message_ref=#{result.message_ref}")
      end
      result
    end

    private

    def header(mail, name)
      mail.header[name]&.value
    end

    def template_headers(mail)
      mail.header.fields.each_with_object({}) do |field, templates|
        next unless field.name.to_s.downcase.start_with?(TEMPLATE_HEADER_PREFIX.downcase)

        templates[field.name.to_s[TEMPLATE_HEADER_PREFIX.length..].downcase] = field.value
      end
    end

    def strip_headers(mail)
      names = mail.header.fields.map(&:name).select do |name|
        name.to_s.casecmp(STORE_HEADER).zero? || name.to_s.casecmp(TYPE_HEADER).zero? ||
          name.to_s.downcase.start_with?(TEMPLATE_HEADER_PREFIX.downcase)
      end
      names.each { |name| mail.header[name] = nil }
    end

    def resolve_store(id)
      (Spree::Store.find_by(id: id) if id.present?) || SpreeNotificationProviders.configuration.default_store
    end
  end
end
