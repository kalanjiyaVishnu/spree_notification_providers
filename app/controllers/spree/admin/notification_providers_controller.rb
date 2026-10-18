# frozen_string_literal: true

module Spree
  module Admin
    # Settings → Notification providers: one tab per channel, providers in
    # priority order, and the providers that can still be added.
    class NotificationProvidersController < Spree::Admin::BaseController
      helper 'spree/admin/notification_masking'

      def index
        authorize! :manage, Spree::NotificationChannelProvider

        @channel = channel_param
        @entries = Spree::NotificationChannelProvider.where(store_id: current_store.id, channel: @channel)
                                                     .order(:position).to_a
        added = @entries.map(&:provider_key)
        @available = SpreeNotificationProviders.providers_for(@channel).reject { |p| added.include?(p.key.to_s) }
      end

      private

      def model_class
        Spree::NotificationChannelProvider
      end

      def channel_param
        Spree::NotificationChannelProvider::CHANNELS.include?(params[:channel]) ? params[:channel] : 'email'
      end
    end
  end
end
