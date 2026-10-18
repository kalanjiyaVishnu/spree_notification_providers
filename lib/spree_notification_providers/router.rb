# frozen_string_literal: true

module SpreeNotificationProviders
  # Sends messages through a store's providers in priority order.
  #
  # One-to-one: tries each enabled provider; providers that are not ready,
  # have no template for the message type, or cannot send its kind are
  # recorded as skipped. Stops at the first :delivered or :unknown, so only a
  # definite failure moves on to the next provider.
  #
  # Bulk: the first enabled, ready, bulk-capable provider only. No failover.
  #
  # Every attempt (and every bulk recipient) is a NotificationDelivery row.
  class Router
    attr_reader :store

    def initialize(store)
      @store = store || SpreeNotificationProviders.configuration.default_store
    end

    def entries(channel)
      Spree::NotificationChannelProvider
        .where(store_id: store.id, channel: channel.to_s)
        .includes(:store)
        .order(:position)
        .to_a
    end

    def deliver(message)
      message_ref = SecureRandom.uuid
      attempts = []
      final_entry = nil
      final_result = nil

      entries(message.channel).select(&:enabled?).each do |entry|
        skip = entry.skip_reason_for(message)
        result = if skip
                   Result.skipped(skip)
                 else
                   call_adapter(entry, template: entry.template_for(message.type, message)) do |adapter, ctx|
                     adapter.deliver(message, ctx)
                   end
                 end
        attempts << record(message, message_ref, attempts.size + 1, entry.provider_key, result)
        next unless result.delivered? || result.unknown?

        final_entry = entry
        final_result = result
        break
      end

      if attempts.empty?
        attempts << record(message, message_ref, 1, nil, Result.skipped('no_provider'))
        outcome = :no_provider
      elsif final_result
        outcome = final_result.outcome
      else
        outcome = attempts.any? { |a| a[:outcome] == :failed } ? :failed : :no_provider
      end

      result = DeliveryResult.new(
        outcome: outcome, message_ref: message_ref, attempts: attempts,
        provider_key: final_entry&.provider_key&.to_sym, provider_message_id: final_result&.provider_message_id
      )
      publish(result, message)
      result
    end

    # One attempt through one entry, ignoring priority and the enabled flag.
    # Used by the admin "Send test" action.
    def deliver_via(entry, message)
      message_ref = SecureRandom.uuid
      missing = entry.missing_inputs
      result = if entry.definition.nil?
                 Result.skipped('unavailable')
               elsif missing.any?
                 Result.skipped("not_ready: missing #{missing.join(', ')}")
               else
                 call_adapter(entry, template: entry.test_template) do |adapter, ctx|
                   adapter.test_message(message.channel, message.to, ctx)
                 end
               end
      attempt = record(message, message_ref, 1, entry.provider_key, result)
      DeliveryResult.new(outcome: result.outcome, message_ref: message_ref, attempts: [attempt],
                         provider_key: entry.provider_key.to_sym, provider_message_id: result.provider_message_id)
    end

    def deliver_bulk(bulk)
      message_ref = SecureRandom.uuid
      entry = entries(bulk.channel).find { |candidate| candidate.enabled? && candidate.skip_reason_for(bulk).nil? }

      unless entry
        insert_bulk_rows(bulk, bulk.recipients, message_ref, nil, Result.skipped('no_provider'))
        return BulkResult.new(outcome: :no_provider, message_ref: message_ref, delivered_count: 0,
                              failed_recipients: bulk.recipients.map { |r| { recipient: r, reason: 'no_provider' } })
      end

      delivered = 0
      failed = []
      bulk.recipients.each_slice(SpreeNotificationProviders.configuration.bulk_batch_size) do |batch|
        result = call_adapter(entry, template: entry.template_for(bulk.type, bulk)) do |adapter, ctx|
          adapter.deliver_bulk(bulk.with_recipients(batch), ctx)
        end
        insert_bulk_rows(bulk, batch, message_ref, entry.provider_key, result)
        if result.delivered?
          delivered += batch.size
        elsif result.failed?
          failed.concat(batch.map { |recipient| { recipient: recipient, reason: result.reason } })
        end
      end

      outcome = if failed.empty? then :delivered
                elsif delivered.zero? then :failed
                else :partial
                end
      BulkResult.new(outcome: outcome, message_ref: message_ref, delivered_count: delivered,
                     failed_recipients: failed, provider_key: entry.provider_key.to_sym)
    end

    def ready_for?(channel, message_type)
      entries(channel).any? { |entry| entry.ready_for?(message_type) }
    end

    def channel_status(channel)
      entries(channel).map do |entry|
        { provider_key: entry.provider_key.to_sym, position: entry.position, status: entry.status,
          missing: entry.missing_inputs }
      end
    end

    private

    def call_adapter(entry, template: nil)
      adapter = entry.definition.adapter_class.new(entry.definition)
      context = entry.context(template: template)
      result = yield(adapter, context)
      result.is_a?(Result) ? result : Result.failed('invalid_adapter_result')
    rescue StandardError => e
      Rails.logger.error("[NotificationProviders] #{entry.provider_key} raised #{e.class}: #{e.message}")
      Result.failed("exception:#{e.class.name}")
    end

    def record(message, message_ref, attempt_number, provider_key, result)
      write_delivery(message, message_ref, attempt_number, provider_key, result)
      { provider_key: provider_key&.to_sym, outcome: result.outcome, reason: result.reason }
    end

    def write_delivery(message, message_ref, attempt_number, provider_key, result)
      Spree::NotificationDelivery.create!(
        store_id: store.id,
        message_ref: message_ref,
        channel: message.channel.to_s,
        provider_key: provider_key&.to_s,
        message_type: message.type.to_s,
        recipient: message.to.presence || '(none)',
        outcome: result.outcome.to_s,
        reason: result.reason,
        provider_message_id: result.provider_message_id,
        attempt_number: attempt_number,
        bulk: false,
        source: message.source.is_a?(ActiveRecord::Base) ? message.source : nil
      )
    rescue StandardError => e
      # A logging failure must never stop a message from being sent.
      Rails.logger.error("[NotificationProviders] could not record delivery: #{e.class}: #{e.message}")
    end

    def insert_bulk_rows(bulk, recipients, message_ref, provider_key, result)
      return if recipients.empty?

      now = Time.current
      source = bulk.source.is_a?(ActiveRecord::Base) ? bulk.source : nil
      rows = recipients.map do |recipient|
        {
          store_id: store.id, message_ref: message_ref, channel: bulk.channel.to_s,
          provider_key: provider_key&.to_s, message_type: bulk.type.to_s, recipient: recipient,
          outcome: result.outcome.to_s, reason: result.reason, provider_message_id: result.provider_message_id,
          attempt_number: 1, bulk: true, source_type: source&.class&.base_class&.name, source_id: source&.id,
          created_at: now
        }
      end
      Spree::NotificationDelivery.insert_all(rows)
    rescue StandardError => e
      Rails.logger.error("[NotificationProviders] could not record bulk deliveries: #{e.class}: #{e.message}")
    end

    def publish(result, message)
      return unless defined?(Spree::Events)

      payload = {
        'store_id' => store.id, 'message_ref' => result.message_ref, 'channel' => message.channel.to_s,
        'provider_key' => result.provider_key&.to_s, 'message_type' => message.type.to_s,
        'source_type' => message.source.is_a?(ActiveRecord::Base) ? message.source.class.base_class.name : nil,
        'source_id' => message.source.is_a?(ActiveRecord::Base) ? message.source.id : nil
      }
      if result.success?
        Spree::Events.publish('notification.delivered', payload)
      elsif result.outcome != :unknown
        Spree::Events.publish('notification.failed', payload.merge('reasons' => result.reasons))
      end
    rescue StandardError => e
      Rails.logger.error("[NotificationProviders] could not publish event: #{e.class}: #{e.message}")
    end
  end
end
