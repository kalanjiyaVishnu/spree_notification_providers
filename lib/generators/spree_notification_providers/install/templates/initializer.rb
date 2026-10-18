# frozen_string_literal: true

SpreeNotificationProviders.configure do |config|
  # Delivery log rows older than this are removed by
  # Spree::NotificationDeliveries::PurgeJob.
  config.delivery_retention_days = 90

  # The Log provider writes messages to the Rails log instead of sending them.
  # config.enable_log_provider = !Rails.env.production?
end

# Each message type gets its own template field on template-based providers.
# SpreeNotificationProviders.register_message_type :order_confirmation,
#                                                  label: 'Order confirmation', channels: %i[email sms]
