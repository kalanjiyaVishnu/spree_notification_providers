# frozen_string_literal: true

module SpreeNotificationProviders
  # Providers, message types and webhook message resolvers known to the app.
  # Lives for the whole process; registrations happen at boot.
  class Registry
    def initialize
      @providers = {}
      @message_types = {}
      @resolvers = Hash.new { |hash, key| hash[key] = [] }
    end

    def register_provider(key, replace: false, &block)
      key = key.to_sym
      raise DuplicateProvider, "provider #{key.inspect} is already registered" if @providers.key?(key) && !replace

      definition = ProviderDefinition.new(key)
      definition.instance_eval(&block) if block
      raise ArgumentError, "provider #{key.inspect} needs an adapter" if definition.adapter.blank?

      @providers[key] = definition
    end

    def unregister_provider(key)
      @providers.delete(key.to_sym)
    end

    def provider(key)
      return nil if key.blank?

      @providers[key.to_sym]
    end

    def providers
      @providers.values
    end

    def providers_for(channel)
      providers.select { |provider| provider.supports?(channel) }
    end

    # Registering the same key again replaces it, so re-running an initializer
    # (e.g. on a code reload) is harmless.
    def register_message_type(key, label:, channels:, bulk: false)
      @message_types[key.to_sym] = MessageType.new(key, label: label, channels: channels, bulk: bulk)
    end

    def message_type(key)
      return nil if key.blank?

      @message_types[key.to_sym]
    end

    def message_types
      @message_types.values
    end

    def message_types_for(channel)
      message_types.select { |type| type.sent_on?(channel) }
    end

    # Webhooks call these when a provider message id has no delivery row (e.g.
    # it was sent before this gem was installed). Each block takes the id and
    # returns the owning Spree::Store, or nil.
    def register_message_resolver(provider_key, &block)
      raise ArgumentError, 'a block is required' unless block

      @resolvers[provider_key.to_sym] << block
    end

    def resolve_message_store(provider_key, provider_message_id)
      @resolvers[provider_key.to_sym].each do |resolver|
        store = resolver.call(provider_message_id)
        return store if store
      end
      nil
    end
  end
end
