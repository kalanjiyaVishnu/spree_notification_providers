# frozen_string_literal: true

module Spree
  module Admin
    module NotificationMaskingHelper
      MASK = '•••'

      # "Set ••••1234" for long values, "Set" for short ones, so a short secret
      # is never mostly revealed.
      def secret_hint(value)
        return nil if value.blank?

        value.to_s.length >= 12 ? "••••#{value.to_s[-4..]}" : ''
      end

      # ka•••@gmail.com, +91•••••3210
      def mask_recipient(value)
        value = value.to_s
        return value if value.blank? || value.start_with?('(')

        if value.include?('@')
          value.split(',').map { |address| mask_email(address.strip) }.join(', ')
        else
          mask_phone(value)
        end
      end

      def notification_status_badge(status)
        classes = {
          ready: 'bg-green-100 text-green-800',
          delivered: 'bg-green-100 text-green-800',
          not_ready: 'bg-amber-100 text-amber-800',
          unknown: 'bg-amber-100 text-amber-800',
          failed: 'bg-red-100 text-red-800',
          unavailable: 'bg-red-100 text-red-800',
          disabled: 'bg-gray-100 text-gray-600',
          skipped: 'bg-gray-100 text-gray-600'
        }
        key = status.to_sym
        scope = %i[ready not_ready disabled unavailable].include?(key) ? 'statuses' : 'outcomes'
        content_tag(:span, t("spree_notification_providers.#{scope}.#{key}"),
                    class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{classes[key]}")
      end

      def notification_channel_label(channel)
        t("spree_notification_providers.channels.#{channel}")
      end

      private

      def mask_email(address)
        local, domain = address.split('@', 2)
        "#{local.to_s.first(2)}#{MASK}@#{domain}"
      end

      def mask_phone(value)
        digits = value.gsub(/\D/, '')
        return "#{MASK}#{digits.last(2)}" if digits.length < 8

        country = digits.length > 10 ? digits[0...(digits.length - 10)] : ''
        "#{"+#{country}" if country.present?}•••••#{digits.last(4)}"
      end
    end
  end
end
