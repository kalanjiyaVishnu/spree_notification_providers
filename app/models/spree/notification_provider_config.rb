# frozen_string_literal: true

module Spree
  # A store's shared inputs for one provider (e.g. the MSG91 auth key that
  # every MSG91 channel uses).
  class NotificationProviderConfig < Spree::Base
    include Spree::NotificationProviderSettings

    has_prefix_id :nprov

    IMPORT_SOURCES = %w[legacy_columns env mixed].freeze

    belongs_to :store, class_name: 'Spree::Store'

    validates :provider_key, presence: true, uniqueness: { scope: :store_id }
    validates :import_source, inclusion: { in: IMPORT_SOURCES }, allow_nil: true
    validate { validate_inputs(shared_inputs) }

    # nil when the provider is no longer registered ("Unavailable").
    def definition
      SpreeNotificationProviders.provider(provider_key)
    end

    def shared_inputs
      definition&.shared_inputs || []
    end

    def channel_providers
      Spree::NotificationChannelProvider.where(store_id: store_id, provider_key: provider_key)
    end
  end
end
