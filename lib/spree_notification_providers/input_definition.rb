# frozen_string_literal: true

module SpreeNotificationProviders
  # One input a provider needs, e.g. MSG91's auth key or SMTP's port.
  #
  # `env` names the environment variable an older setup kept this value in. It
  # is read by the importers only; adapters never read ENV.
  class InputDefinition
    TYPES = %i[string integer email phone url select boolean].freeze
    EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP
    PHONE_FORMAT = /\A\+?[1-9]\d{9,14}\z/

    attr_reader :name, :provider_key, :scope, :type, :format, :default, :env, :options

    def initialize(name, provider_key:, scope:, type: :string, required: false, secret: false, format: nil,
                   default: nil, env: nil, options: nil, label: nil, help: nil)
      raise ArgumentError, "unknown input type #{type.inspect}" unless TYPES.include?(type)

      @name = name.to_sym
      @provider_key = provider_key.to_sym
      @scope = scope
      @type = type
      @required = required
      @secret = secret
      @format = format
      @default = default
      @env = env
      @options = options
      @label = label
      @help = help
    end

    def required? = @required
    def secret? = @secret
    def key = name.to_s

    def label
      I18n.t("spree_notification_providers.providers.#{provider_key}.inputs.#{name}.label",
             default: @label || name.to_s.humanize)
    end

    def help
      I18n.t("spree_notification_providers.providers.#{provider_key}.inputs.#{name}.help", default: @help.to_s)
    end

    # The value an adapter sees: the stored value, else the default, cast.
    def resolve(raw)
      value = raw.to_s.strip.presence || default
      return nil if value.nil?

      case type
      when :integer then value.to_i
      when :boolean then ActiveModel::Type::Boolean.new.cast(value)
      else value.to_s
      end
    end

    # nil when valid (blank counts as valid; readiness reports missing inputs).
    def validate(raw)
      value = raw.to_s.strip
      return nil if value.empty?

      message = case type
                when :integer then 'must be a whole number' unless value.match?(/\A\d+\z/)
                when :email then 'must be an email address' unless value.match?(EMAIL_FORMAT)
                when :phone then 'must be a phone number with country code' unless value.delete(' -').match?(PHONE_FORMAT)
                when :url then 'must be a URL' unless value.match?(%r{\Ahttps?://\S+\z})
                when :boolean then 'must be true or false' unless %w[true false 1 0].include?(value)
                when :select then 'is not an allowed option' unless Array(options).map(&:to_s).include?(value)
                end
      message ||= 'is not in the expected format' if format && !value.match?(format)
      message
    end
  end
end
