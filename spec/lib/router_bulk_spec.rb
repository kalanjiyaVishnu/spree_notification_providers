# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'SpreeNotificationProviders.deliver_bulk' do
  let(:store) { @default_store }
  let(:outcomes) { {} }
  let(:calls) { [] }

  before do
    stub_const('BulkSpecAdapter', Class.new(SpreeNotificationProviders::Adapters::Base))
    map = outcomes
    log = calls
    BulkSpecAdapter.define_method(:deliver_bulk) do |bulk, context|
      log << [definition.key, bulk.recipients.size, context.template]
      map.fetch(definition.key, SpreeNotificationProviders::Result.delivered('batch'))
    end

    SpreeNotificationProviders.register_provider(:bulk_a, replace: true) do
      adapter 'BulkSpecAdapter'
      channel :sms, kinds: %i[template bulk]
    end
    SpreeNotificationProviders.register_provider(:bulk_b, replace: true) do
      adapter 'BulkSpecAdapter'
      channel :sms, kinds: %i[template bulk]
    end
    SpreeNotificationProviders.register_provider(:no_bulk, replace: true) do
      adapter 'BulkSpecAdapter'
      channel :sms, kinds: %i[template]
    end
  end

  after { %i[bulk_a bulk_b no_bulk].each { |key| SpreeNotificationProviders.unregister_provider(key) } }

  def entry(key, **attrs)
    create(:notification_channel_provider, store: store, channel: 'sms', provider_key: key.to_s, **attrs)
  end

  def bulk(count)
    SpreeNotificationProviders::BulkMessage.new(
      channel: :sms, type: :customer_blast, recipients: (1..count).map { |i| format('98765%05d', i) },
      templates: { bulk_a: 'flow-x' }, source: store
    )
  end

  it 'uses the first enabled provider that supports bulk, in batches of 100' do
    entry(:no_bulk)
    entry(:bulk_a)
    entry(:bulk_b)

    result = SpreeNotificationProviders.deliver_bulk(store: store, message: bulk(250))

    expect(calls).to eq([[:bulk_a, 100, 'flow-x'], [:bulk_a, 100, 'flow-x'], [:bulk_a, 50, 'flow-x']])
    expect(result).to have_attributes(outcome: :delivered, delivered_count: 250, provider_key: :bulk_a)
    expect(Spree::NotificationDelivery.where(message_ref: result.message_ref, bulk: true, outcome: 'delivered').count)
      .to eq(250)
  end

  it 'records each recipient of a rejected batch as failed and never fails over' do
    entry(:bulk_a)
    entry(:bulk_b)
    outcomes[:bulk_a] = SpreeNotificationProviders::Result.failed('http_400: bad template')

    result = SpreeNotificationProviders.deliver_bulk(store: store, message: bulk(3))

    expect(calls.map(&:first)).to eq([:bulk_a])
    expect(result.outcome).to eq(:failed)
    expect(result.failed_recipients.size).to eq(3)
    expect(result.failed_recipients.first[:reason]).to eq('http_400: bad template')
    rows = Spree::NotificationDelivery.where(message_ref: result.message_ref)
    expect(rows.pluck(:outcome).uniq).to eq(['failed'])
    expect(rows.first).to have_attributes(source_type: 'Spree::Store', source_id: store.id, bulk: true)
  end

  it 'records every recipient as skipped when no provider is ready' do
    entry(:no_bulk)

    result = SpreeNotificationProviders.deliver_bulk(store: store, message: bulk(2))

    expect(result.outcome).to eq(:no_provider)
    expect(Spree::NotificationDelivery.where(message_ref: result.message_ref).pluck(:outcome, :reason))
      .to eq([%w[skipped no_provider], %w[skipped no_provider]])
  end

  it 'writes the rows with insert_all' do
    entry(:bulk_a)
    allow(Spree::NotificationDelivery).to receive(:insert_all).and_call_original

    SpreeNotificationProviders.deliver_bulk(store: store, message: bulk(150))

    expect(Spree::NotificationDelivery).to have_received(:insert_all).twice
  end
end
