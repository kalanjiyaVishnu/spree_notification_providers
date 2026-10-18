# frozen_string_literal: true

module SpreeNotificationProviders
  # One message to one recipient.
  #
  # kind:
  #   :otp      - a one-time code (`code`, `expiry_minutes`)
  #   :template - a provider-side template filled with `variables`
  #   :html     - a rendered email (`subject` + `html`, or a ready `mail`)
  class Message
    KINDS = %i[otp template html].freeze

    attr_reader :channel, :type, :kind, :to, :to_name, :code, :expiry_minutes, :variables, :subject, :html,
                :mail, :from_email, :from_name, :reply_to, :templates, :source

    def initialize(channel:, type:, to:, kind: nil, to_name: nil, code: nil, expiry_minutes: nil, variables: {},
                   subject: nil, html: nil, mail: nil, from_email: nil, from_name: nil, reply_to: nil,
                   templates: {}, source: nil)
      @channel = SpreeNotificationProviders.channel!(channel)
      @type = type.to_sym
      @to = to.to_s.strip
      @to_name = to_name
      @code = code&.to_s
      @expiry_minutes = expiry_minutes
      @variables = variables || {}
      @subject = subject
      @html = html
      @mail = mail
      @from_email = from_email.presence
      @from_name = from_name.presence
      @reply_to = reply_to.presence
      @templates = (templates || {}).transform_keys(&:to_s).compact_blank
      @source = source
      @kind = (kind || infer_kind).to_sym
      raise ArgumentError, "unknown kind #{@kind.inspect}" unless KINDS.include?(@kind)
    end

    # A template id given for this message only, beating the channel's
    # configured template for the type.
    def template_override(provider_key)
      templates[provider_key.to_s]
    end

    def bulk? = false

    private

    def infer_kind
      return :html if html.present? || mail.present?
      return :otp if code.present?

      :template
    end
  end
end
