# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Gupshup delivery webhook', type: :request do
  let(:store) { @default_store }
  let(:secret) { 'hook-secret-abcdef' }
  let!(:entry) { create(:notification_channel_provider, :gupshup, store: store) }
  let!(:delivery) do
    create(:notification_delivery, store: store, channel: 'whatsapp', provider_key: 'gupshup',
                                   message_type: 'otp_code', recipient: '+919876543210', provider_message_id: 'gs-abc')
  end

  before { allow(Spree::Events).to receive(:publish) }

  def failed_event(id: 'gs-abc', key: 'gsId', reason: 'Number Does Not Exists On WhatsApp')
    { type: 'message-event', payload: { key => id, type: 'failed', payload: { code: 1002, reason: reason } } }
  end

  def deliver(body, secret_param: secret)
    post "/webhooks/gupshup?secret=#{secret_param}", params: body.to_json,
                                                    headers: { 'Content-Type' => 'application/json' }
  end

  it 'marks the delivery failed and publishes notification.delivery_failed' do
    deliver(failed_event(reason: 'x' * 300))

    expect(response).to have_http_status(:ok)
    expect(delivery.reload).to have_attributes(outcome: 'failed', reason: 'x' * 117 + '...')
    expect(Spree::Events).to have_received(:publish).with(
      'notification.delivery_failed',
      hash_including('store_id' => store.id, 'delivery_id' => delivery.id, 'provider_message_id' => 'gs-abc')
    )
  end

  it 'accepts the message id under payload.id' do
    deliver(failed_event(key: 'id'))

    expect(delivery.reload.outcome).to eq('failed')
  end

  it "checks the secret against the owning store's webhook secret" do
    deliver(failed_event, secret_param: 'nope')
    expect(response).to have_http_status(:not_found)

    other = create(:store)
    create(:notification_channel_provider, :gupshup, store: other,
                                                     shared_secrets: { api_key: 'k', webhook_secret: 'other-store-secret' })
    deliver(failed_event, secret_param: 'other-store-secret')
    expect(response).to have_http_status(:not_found)
    expect(delivery.reload.outcome).to eq('delivered')
  end

  it '404s when the store has no webhook secret' do
    entry.provider_config.update!(secret_settings: { 'api_key' => 'k' }.to_json)

    deliver(failed_event, secret_param: '')

    expect(response).to have_http_status(:not_found)
  end

  it 'ignores events that are not failures' do
    deliver({ type: 'message-event', payload: { gsId: 'gs-abc', type: 'delivered' } })

    expect(response).to have_http_status(:ok)
    expect(delivery.reload.outcome).to eq('delivered')
    expect(Spree::Events).not_to have_received(:publish)
  end

  it '404s for an id no delivery or resolver knows' do
    deliver(failed_event(id: 'gs-unknown'))

    expect(response).to have_http_status(:not_found)
  end

  it 'asks registered resolvers for messages without a delivery row' do
    registry = SpreeNotificationProviders.registry
    resolvers = registry.instance_variable_get(:@resolvers)
    original = resolvers[:gupshup].dup
    SpreeNotificationProviders.register_message_resolver(:gupshup) { |id| store if id == 'gs-legacy' }

    deliver(failed_event(id: 'gs-legacy'))

    expect(response).to have_http_status(:ok)
    expect(Spree::Events).to have_received(:publish).with(
      'notification.delivery_failed',
      hash_including('store_id' => store.id, 'delivery_id' => nil, 'provider_message_id' => 'gs-legacy')
    )
  ensure
    resolvers[:gupshup] = original if resolvers
  end
end
