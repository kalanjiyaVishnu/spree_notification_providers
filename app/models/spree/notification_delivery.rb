# frozen_string_literal: true

module Spree
  # One attempt to send a message (or one recipient of a bulk send).
  class NotificationDelivery < Spree::Base
    has_prefix_id :ndel

    OUTCOMES = %w[delivered failed unknown skipped].freeze

    belongs_to :store, class_name: 'Spree::Store'
    belongs_to :source, polymorphic: true, optional: true

    validates :channel, :message_type, :recipient, :message_ref, presence: true
    validates :outcome, inclusion: { in: OUTCOMES }

    before_validation { self.reason = reason.to_s.truncate(255).presence }

    scope :older_than, ->(days) { where(created_at: ...days.days.ago) }
    scope :newest_first, -> { order(created_at: :desc, id: :desc) }

    # `recipient` is deliberately not searchable: it is masked on screen.
    self.whitelisted_ransackable_attributes = %w[channel provider_key outcome message_type created_at bulk]

    def self.ransackable_attributes(_auth_object = nil)
      whitelisted_ransackable_attributes
    end

    def self.ransackable_associations(_auth_object = nil)
      []
    end

    # Only a provider callback may turn a delivered message into a failure.
    def mark_failed!(reason)
      return false unless outcome == 'delivered'

      update!(outcome: 'failed', reason: reason.presence || 'provider_reported_failure')
    end
  end
end
