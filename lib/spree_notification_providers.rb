# frozen_string_literal: true

require 'spree/core'
require 'securerandom'

require 'spree_notification_providers/version'

# Per-channel notification providers with priority and failover.
#
# Providers (MSG91, SMTP, Gupshup, or one an app registers) declare the
# channels they serve and the inputs they need. Each store enables providers
# per channel and orders them; `deliver` tries them in that order and moves on
# only when a provider definitely did not take the message. See README.
module SpreeNotificationProviders
  CHANNELS = %i[email sms whatsapp].freeze

  class Error < StandardError; end
  class DuplicateProvider < Error; end
  class UnknownChannel < Error; end
  class DeliveryFailed < Error; end
end

require 'spree_notification_providers/configuration'
require 'spree_notification_providers/input_definition'
require 'spree_notification_providers/provider_definition'
require 'spree_notification_providers/message_type'
require 'spree_notification_providers/registry'
require 'spree_notification_providers/result'
require 'spree_notification_providers/message'
require 'spree_notification_providers/bulk_message'
require 'spree_notification_providers/http'
require 'spree_notification_providers/adapters/base'
require 'spree_notification_providers/adapters/http_outcome'
require 'spree_notification_providers/adapters/log'
require 'spree_notification_providers/adapters/msg91'
require 'spree_notification_providers/adapters/smtp'
require 'spree_notification_providers/adapters/gupshup'
require 'spree_notification_providers/router'
require 'spree_notification_providers/mail_delivery_method'
require 'spree_notification_providers/importers/env_importer'

module SpreeNotificationProviders
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def registry
      @registry ||= Registry.new
    end

    delegate :register_provider, :unregister_provider, :provider, :providers, :providers_for,
             :register_message_type, :message_type, :message_types, :message_types_for,
             :register_message_resolver, :resolve_message_store, to: :registry

    # Sends a one-to-one message through the store's providers for its channel,
    # in priority order. Never raises for provider failures.
    def deliver(store:, message:)
      Router.new(store).deliver(message)
    end

    # Sends to many recipients through the top-priority ready provider only.
    def deliver_bulk(store:, message:)
      Router.new(store).deliver_bulk(message)
    end

    def ready_for?(store, channel, message_type)
      Router.new(store).ready_for?(channel, message_type)
    end

    def channel_status(store, channel)
      Router.new(store).channel_status(channel)
    end

    def channel!(value)
      channel = value.to_s.to_sym
      raise UnknownChannel, "unknown channel #{value.inspect}" unless CHANNELS.include?(channel)

      channel
    end
  end
end

require 'spree_notification_providers/providers/msg91'
require 'spree_notification_providers/providers/smtp'
require 'spree_notification_providers/providers/gupshup'
require 'spree_notification_providers/providers/log'
require 'spree_notification_providers/message_types'
require 'spree_notification_providers/engine'
