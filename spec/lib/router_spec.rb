# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SpreeNotificationProviders::Router do
  let(:store) { @default_store }

  # Adapters whose outcome each example sets.
  let(:outcomes) { {} }
  let(:calls) { [] }

  before do
    stub_const('RouterSpecAdapter', Class.new(SpreeNotificationProviders::Adapters::Base))
    outcome_map = outcomes
    call_log = calls
    RouterSpecAdapter.define_method(:deliver) do |message, context|
      call_log << [definition.key, message.to, context.template]
      value = outcome_map.fetch(definition.key, SpreeNotificationProviders::Result.delivered("id-#{definition.key}"))
      value.respond_to?(:call) ? value.call : value
    end
    RouterSpecAdapter.define_method(:deliver_bulk) do |bulk, _context|
      call_log << [definition.key, bulk.recipients]
      value = outcome_map.fetch(definition.key, SpreeNotificationProviders::Result.delivered('bulk-id'))
      value.respond_to?(:call) ? value.call : value
    end

    %i[alpha beta gamma].each do |key|
      SpreeNotificationProviders.register_provider(key, replace: true) do
        adapter 'RouterSpecAdapter'
        channel :sms, kinds: %i[otp template bulk]
      end
    end
  end

  after { %i[alpha beta gamma].each { |key| SpreeNotificationProviders.unregister_provider(key) } }

  def entry(key, **attrs)
    create(:notification_channel_provider, store: store, channel: 'sms', provider_key: key.to_s, **attrs)
  end

  def message(**attrs)
    SpreeNotificationProviders::Message.new(channel: :sms, type: :otp_code, to: '+919876543210', code: '111222',
                                            **attrs)
  end

  def deliver(msg = message)
    SpreeNotificationProviders.deliver(store: store, message: msg)
  end

  it 'tries providers in position order and stops at the first delivery' do
    entry(:beta)
    entry(:alpha)

    result = deliver

    expect(result).to be_success
    expect(result.provider_key).to eq(:beta)
    expect(result.provider_message_id).to eq('id-beta')
    expect(calls.map(&:first)).to eq([:beta])
  end

  it 'ignores disabled providers' do
    entry(:alpha, enabled: false)
    entry(:beta)

    expect(deliver.provider_key).to eq(:beta)
    expect(calls.map(&:first)).to eq([:beta])
  end

  it 'moves to the next provider on a definite failure' do
    entry(:alpha)
    entry(:beta)
    outcomes[:alpha] = SpreeNotificationProviders::Result.failed('http_401')

    result = deliver

    expect(result.provider_key).to eq(:beta)
    expect(result.attempts.map { |a| [a[:provider_key], a[:outcome]] }).to eq([%i[alpha failed], %i[beta delivered]])
  end

  it 'stops without failover on an unknown outcome' do
    entry(:alpha)
    entry(:beta)
    outcomes[:alpha] = SpreeNotificationProviders::Result.unknown('read_timeout')

    result = deliver

    expect(result.outcome).to eq(:unknown)
    expect(result).not_to be_retryable
    expect(calls.map(&:first)).to eq([:alpha])
  end

  it 'reports :failed with every reason when all providers fail' do
    entry(:alpha)
    entry(:beta)
    outcomes[:alpha] = SpreeNotificationProviders::Result.failed('http_401')
    outcomes[:beta] = SpreeNotificationProviders::Result.failed('http_500: down')

    result = deliver

    expect(result.outcome).to eq(:failed)
    expect(result).to be_retryable
    expect(result.reasons).to eq(['alpha: http_401', 'beta: http_500: down'])
  end

  it 'reports :no_provider and records one row when the channel has no entries' do
    result = deliver

    expect(result.outcome).to eq(:no_provider)
    expect(Spree::NotificationDelivery.where(message_ref: result.message_ref).pluck(:outcome, :reason))
      .to eq([%w[skipped no_provider]])
  end

  it 'records a not-ready provider as skipped and moves on' do
    SpreeNotificationProviders.register_provider(:alpha, replace: true) do
      adapter 'RouterSpecAdapter'
      channel(:sms, kinds: %i[otp]) { input :token, required: true }
    end
    entry(:alpha)
    entry(:beta)

    result = deliver

    expect(result.attempts.first).to include(provider_key: :alpha, outcome: :skipped, reason: 'not_ready: missing Token')
    expect(result.provider_key).to eq(:beta)
  end

  it 'records a provider with no template for the type as skipped' do
    SpreeNotificationProviders.register_provider(:alpha, replace: true) do
      adapter 'RouterSpecAdapter'
      channel :sms, kinds: %i[otp], template_required: true
    end
    entry(:alpha)
    entry(:beta)

    expect(deliver.attempts.first).to include(provider_key: :alpha, outcome: :skipped, reason: 'no_template')
  end

  it 'records an unsupported message kind as skipped' do
    SpreeNotificationProviders.register_provider(:alpha, replace: true) do
      adapter 'RouterSpecAdapter'
      channel :sms, kinds: %i[template]
    end
    entry(:alpha)
    entry(:beta)

    expect(deliver.attempts.first).to include(provider_key: :alpha, outcome: :skipped, reason: 'unsupported')
  end

  it 'passes the template for the message type to the adapter' do
    entry(:alpha, templates: { 'otp_code' => 'tmpl-otp' })

    deliver

    expect(calls.first.last).to eq('tmpl-otp')
  end

  it 'records an adapter exception as a failure and keeps going' do
    entry(:alpha)
    entry(:beta)
    outcomes[:alpha] = -> { raise ArgumentError, 'boom' }

    result = deliver

    expect(result.attempts.first).to include(outcome: :failed, reason: 'exception:ArgumentError')
    expect(result.provider_key).to eq(:beta)
  end

  it 'writes one delivery row per attempt sharing a message ref' do
    entry(:alpha)
    entry(:beta)
    outcomes[:alpha] = SpreeNotificationProviders::Result.failed('http_401')

    result = deliver(message(source: store))

    rows = Spree::NotificationDelivery.where(message_ref: result.message_ref).order(:attempt_number)
    expect(rows.pluck(:provider_key, :outcome, :attempt_number)).to eq([['alpha', 'failed', 1], ['beta', 'delivered', 2]])
    expect(rows.first).to have_attributes(channel: 'sms', message_type: 'otp_code', recipient: '+919876543210',
                                          source: store)
  end

  it 'publishes notification.delivered and notification.failed' do
    allow(Spree::Events).to receive(:publish)
    entry(:alpha)

    deliver
    outcomes[:alpha] = SpreeNotificationProviders::Result.failed('http_401')
    deliver

    expect(Spree::Events).to have_received(:publish).with('notification.delivered', hash_including('provider_key' => 'alpha'))
    expect(Spree::Events).to have_received(:publish).with('notification.failed', hash_including('reasons' => ['alpha: http_401']))
  end

  describe 'readiness queries' do
    it 'answers ready_for? and channel_status' do
      entry(:alpha, enabled: false)
      entry(:beta)

      expect(SpreeNotificationProviders.ready_for?(store, :sms, :otp_code)).to be(true)
      expect(SpreeNotificationProviders.channel_status(store, :sms)).to eq([
                                                                             { provider_key: :alpha, position: 1, status: :disabled, missing: [] },
                                                                             { provider_key: :beta, position: 2, status: :ready, missing: [] }
                                                                           ])
    end
  end
end
