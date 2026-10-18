# frozen_string_literal: true

module SpreeNotificationProviders
  # What one provider can do on one channel.
  class ChannelCapability
    KINDS = %i[otp template html bulk].freeze

    attr_reader :provider, :channel, :kinds, :inputs, :template_format

    def initialize(provider, channel, kinds:, template_required: false, template_format: nil)
      unknown = Array(kinds) - KINDS
      raise ArgumentError, "unknown kinds #{unknown.inspect}" if unknown.any?

      @provider = provider
      @channel = channel
      @kinds = Array(kinds)
      @template_required = template_required
      @template_format = template_format
      @inputs = []
      @missing_checks = []
    end

    def template_required? = @template_required

    def supports_kind?(kind)
      kinds.include?(kind.to_sym)
    end

    # DSL
    def input(name, **options)
      @inputs << InputDefinition.new(name, provider_key: provider.key, scope: channel, **options)
    end

    # Extra readiness rules that depend on several values at once. The block
    # receives (values, templates) and returns labels of what is missing.
    def missing_check(&block)
      @missing_checks << block
    end

    def extra_missing(values, templates)
      @missing_checks.flat_map { |check| Array(check.call(values, templates)) }
    end

    def template_valid?(value)
      template_format.nil? || value.to_s.match?(template_format)
    end
  end

  # A registered provider. Built by `SpreeNotificationProviders.register_provider`.
  class ProviderDefinition
    attr_reader :key, :channels, :shared_inputs

    def initialize(key)
      @key = key.to_sym
      @channels = {}
      @shared_inputs = []
    end

    # DSL ------------------------------------------------------------------

    def label(value = nil)
      return @label = value if value

      I18n.t("spree_notification_providers.providers.#{key}.label", default: @label || key.to_s.titleize)
    end

    def adapter(value = nil)
      return @adapter = value if value

      @adapter
    end

    def shared_input(name, **options)
      @shared_inputs << InputDefinition.new(name, provider_key: key, scope: :shared, **options)
    end

    def channel(name, kinds:, template_required: false, template_format: nil, &block)
      channel = SpreeNotificationProviders.channel!(name)
      capability = ChannelCapability.new(self, channel, kinds: kinds, template_required: template_required,
                                                        template_format: template_format)
      capability.instance_eval(&block) if block
      @channels[channel] = capability
    end

    # Queries --------------------------------------------------------------

    def adapter_class
      @adapter.is_a?(String) ? @adapter.constantize : @adapter
    end

    def supports?(channel)
      channels.key?(channel.to_s.to_sym)
    end

    def capability(channel)
      channels[channel.to_s.to_sym]
    end

    def channel_names
      channels.keys
    end
  end
end
