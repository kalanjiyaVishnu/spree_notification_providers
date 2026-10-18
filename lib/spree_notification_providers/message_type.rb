# frozen_string_literal: true

module SpreeNotificationProviders
  # A kind of message an app sends, e.g. :otp_code or :back_in_stock. Each one
  # gets its own template field on template-based providers.
  class MessageType
    attr_reader :key, :channels

    def initialize(key, label:, channels:, bulk: false)
      @key = key.to_sym
      @label = label
      @channels = Array(channels).map { |c| SpreeNotificationProviders.channel!(c) }
      @bulk = bulk
    end

    def bulk? = @bulk

    def label
      I18n.t("spree_notification_providers.message_types.#{key}", default: @label)
    end

    def sent_on?(channel)
      channels.include?(channel.to_s.to_sym)
    end
  end
end
