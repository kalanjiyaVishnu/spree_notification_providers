# frozen_string_literal: true

module SpreeNotificationProviders
  # What one adapter call returned.
  #
  # :delivered - the provider accepted the message.
  # :failed    - the provider definitely did not accept it; safe to try the next.
  # :unknown   - it may have reached the provider; trying another could duplicate it.
  # :skipped   - recorded by the router for providers it did not call.
  #
  # `reason` is a short code or provider message. Never put credentials or full
  # response bodies in it.
  class Result
    OUTCOMES = %i[delivered failed unknown skipped].freeze

    attr_reader :outcome, :provider_message_id, :reason

    def self.delivered(provider_message_id = nil) = new(outcome: :delivered, provider_message_id: provider_message_id)
    def self.failed(reason) = new(outcome: :failed, reason: reason)
    def self.unknown(reason) = new(outcome: :unknown, reason: reason)
    def self.skipped(reason) = new(outcome: :skipped, reason: reason)

    def initialize(outcome:, provider_message_id: nil, reason: nil)
      raise ArgumentError, "unknown outcome #{outcome.inspect}" unless OUTCOMES.include?(outcome)

      @outcome = outcome
      @provider_message_id = provider_message_id.presence&.to_s
      @reason = reason.presence&.to_s&.truncate(255)
    end

    OUTCOMES.each do |name|
      define_method(:"#{name}?") { outcome == name }
    end
  end

  # What `SpreeNotificationProviders.deliver` returns.
  class DeliveryResult
    attr_reader :outcome, :provider_key, :provider_message_id, :message_ref, :attempts

    def initialize(outcome:, message_ref:, attempts:, provider_key: nil, provider_message_id: nil)
      @outcome = outcome
      @message_ref = message_ref
      @attempts = attempts
      @provider_key = provider_key
      @provider_message_id = provider_message_id
    end

    def success? = outcome == :delivered

    # True only when no provider can have taken the message, so sending again
    # (or through another channel) cannot duplicate it.
    def retryable? = %i[failed no_provider].include?(outcome)

    def reasons
      attempts.filter_map { |attempt| "#{attempt[:provider_key] || 'none'}: #{attempt[:reason]}" if attempt[:reason] }
    end
  end

  # What `SpreeNotificationProviders.deliver_bulk` returns.
  class BulkResult
    attr_reader :outcome, :provider_key, :message_ref, :delivered_count, :failed_recipients

    def initialize(outcome:, message_ref:, delivered_count:, failed_recipients:, provider_key: nil)
      @outcome = outcome
      @message_ref = message_ref
      @delivered_count = delivered_count
      @failed_recipients = failed_recipients
      @provider_key = provider_key
    end

    def success? = failed_recipients.empty? && outcome != :no_provider
  end
end
