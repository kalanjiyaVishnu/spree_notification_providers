# frozen_string_literal: true

module Spree
  module PermissionSets
    # Grants the Notification providers and Delivery log screens to roles that
    # are not full super users. Assign in the app's Spree initializer:
    #
    #   Spree.permissions.assign(:admin, [Spree::PermissionSets::NotificationProviderManagement])
    #
    # Delivery rows are written by the router, never by an admin, so :manage
    # on them means "may open the Delivery log".
    class NotificationProviderManagement < Base
      def activate!
        can :manage, Spree::NotificationProviderConfig
        can :manage, Spree::NotificationChannelProvider
        can :manage, Spree::NotificationDelivery
      end
    end
  end
end
