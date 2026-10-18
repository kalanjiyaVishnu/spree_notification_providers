# frozen_string_literal: true

module SpreeNotificationProviders
  module StoreDecorator
    def self.prepended(base)
      base.has_many :notification_provider_configs, class_name: 'Spree::NotificationProviderConfig',
                                                    dependent: :destroy
      base.has_many :notification_channel_providers, class_name: 'Spree::NotificationChannelProvider',
                                                     dependent: :destroy
      base.has_many :notification_deliveries, class_name: 'Spree::NotificationDelivery', dependent: :delete_all
    end
  end
end

Spree::Store.prepend(SpreeNotificationProviders::StoreDecorator) unless Spree::Store.ancestors.include?(SpreeNotificationProviders::StoreDecorator)
