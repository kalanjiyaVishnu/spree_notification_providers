# frozen_string_literal: true

module SpreeNotificationProviders
  # One template message to many recipients (e.g. a customer group blast).
  # The same `variables` apply to every recipient.
  class BulkMessage
    attr_reader :channel, :type, :recipients, :variables, :templates, :source, :from_email, :from_name

    def initialize(channel:, type:, recipients:, variables: {}, templates: {}, source: nil, from_email: nil,
                   from_name: nil)
      @channel = SpreeNotificationProviders.channel!(channel)
      @type = type.to_sym
      @recipients = Array(recipients).map { |r| r.to_s.strip }.compact_blank.uniq
      @variables = variables || {}
      @templates = (templates || {}).transform_keys(&:to_s).compact_blank
      @source = source
      @from_email = from_email.presence
      @from_name = from_name.presence
    end

    def kind = :bulk
    def bulk? = true

    def template_override(provider_key)
      templates[provider_key.to_s]
    end

    def with_recipients(batch)
      self.class.new(channel: channel, type: type, recipients: batch, variables: variables, templates: templates,
                     source: source, from_email: from_email, from_name: from_name)
    end
  end
end
