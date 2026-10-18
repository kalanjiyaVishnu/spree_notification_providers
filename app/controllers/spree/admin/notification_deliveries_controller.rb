# frozen_string_literal: true

module Spree
  module Admin
    # Settings → Delivery log: every send attempt for the current store,
    # grouped by message. Read-only; recipients are masked.
    class NotificationDeliveriesController < Spree::Admin::BaseController
      include Pagy::Method

      helper 'spree/admin/notification_masking'

      PER_PAGE = 50

      def index
        authorize! :manage, Spree::NotificationDelivery

        @search = scope.ransack(params[:q])
        filtered = @search.result
        refs = filtered.group(:message_ref).order(Arel.sql('MAX(created_at) DESC')).select(:message_ref)
        # Grouped rows have no simple count, so page without one.
        @pagy, page_refs = pagy(:countless, refs, limit: PER_PAGE)
        @groups = build_groups(page_refs.map(&:message_ref))
      end

      def show
        authorize! :manage, Spree::NotificationDelivery

        all = scope.where(message_ref: params[:message_ref]).order(:attempt_number, :id)
        raise ActiveRecord::RecordNotFound if all.none?

        @message_ref = params[:message_ref]
        @first = all.first
        @pagy, @deliveries = pagy(:offset, all, limit: PER_PAGE)
      end

      private

      def model_class
        Spree::NotificationDelivery
      end

      def scope
        Spree::NotificationDelivery.where(store_id: current_store.id)
      end

      Group = Struct.new(:message_ref, :attempts, :bulk_first, :bulk_counts, keyword_init: true) do
        def bulk? = bulk_first.present?
        def first = bulk_first || attempts.first
        def final = bulk? ? nil : (attempts.reverse.find { |a| a.outcome.in?(%w[delivered unknown]) } || attempts.last)
      end

      # One-to-one messages load their few attempts; a bulk send loads one
      # sample row and counts per outcome, never every recipient.
      def build_groups(refs)
        attempts = scope.where(message_ref: refs, bulk: false).order(:attempt_number, :id).group_by(&:message_ref)
        bulk_first = scope.where(message_ref: refs, bulk: true).select('DISTINCT ON (message_ref) *')
                          .order(:message_ref, :id).index_by(&:message_ref)
        counts = scope.where(message_ref: bulk_first.keys).group(:message_ref, :outcome).count

        refs.filter_map do |ref|
          next unless attempts[ref] || bulk_first[ref]

          bulk_counts = counts.select { |(r, _), _| r == ref }.transform_keys(&:last)
          Group.new(message_ref: ref, attempts: attempts[ref] || [], bulk_first: bulk_first[ref], bulk_counts: bulk_counts)
        end
      end
    end
  end
end
