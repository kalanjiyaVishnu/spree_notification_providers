# frozen_string_literal: true

module Spree
  module NotificationDeliveries
    # Removes Delivery log rows older than `delivery_retention_days`.
    # Schedule daily (e.g. sidekiq-cron: `0 4 * * *`).
    class PurgeJob < ActiveJob::Base
      queue_as :default

      BATCH_SIZE = 1_000

      def perform
        days = SpreeNotificationProviders.configuration.delivery_retention_days
        deleted = 0
        loop do
          ids = Spree::NotificationDelivery.older_than(days).limit(BATCH_SIZE).pluck(:id)
          break if ids.empty?

          deleted += Spree::NotificationDelivery.where(id: ids).delete_all
        end
        Rails.logger.info("[NotificationProviders] purged #{deleted} delivery rows older than #{days} days")
        deleted
      end
    end
  end
end
