# frozen_string_literal: true

module SpreeNotificationProviders
  # Set in config/initializers/spree_notification_providers.rb:
  #
  #   SpreeNotificationProviders.configure do |config|
  #     config.delivery_retention_days = 90
  #   end
  class Configuration
    attr_reader :delivery_retention_days
    attr_accessor :enable_log_provider, :http_timeout_seconds, :default_store_resolver, :bulk_batch_size

    def initialize
      @delivery_retention_days = 90
      @enable_log_provider = !(defined?(Rails) && Rails.env.production?)
      @http_timeout_seconds = 5
      @bulk_batch_size = 100
      @default_store_resolver = -> { Spree::Current.store || Spree::Store.default }
    end

    def delivery_retention_days=(value)
      days = Integer(value)
      raise ArgumentError, 'delivery_retention_days must be >= 1' if days < 1

      @delivery_retention_days = days
    end

    def default_store
      default_store_resolver.call
    end
  end
end
