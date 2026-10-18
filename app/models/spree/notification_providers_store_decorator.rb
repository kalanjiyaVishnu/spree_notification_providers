# frozen_string_literal: true

module Spree
  # File name matches the constant so Zeitwerk can eager-load it in any app.
  module NotificationProvidersStoreDecorator
    def self.prepended(base)
      base.has_many :notification_provider_configs, class_name: 'Spree::NotificationProviderConfig',
                                                    dependent: :destroy
      base.has_many :notification_channel_providers, class_name: 'Spree::NotificationChannelProvider',
                                                     dependent: :destroy
      base.has_many :notification_deliveries, class_name: 'Spree::NotificationDelivery', dependent: :delete_all
    end
  end

  Spree::Store.prepend(NotificationProvidersStoreDecorator) unless Spree::Store.ancestors.include?(NotificationProvidersStoreDecorator)
end
