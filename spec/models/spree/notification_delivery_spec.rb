# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::NotificationDelivery do
  let(:store) { @default_store }

  it 'caps the reason at 255 characters' do
    delivery = create(:notification_delivery, store: store, reason: 'x' * 1000)

    expect(delivery.reason.length).to eq(255)
  end

  it 'only lets a delivered row become failed' do
    delivered = create(:notification_delivery, store: store, outcome: 'delivered')
    skipped = create(:notification_delivery, store: store, outcome: 'skipped')

    expect(delivered.mark_failed!('number not on WhatsApp')).to be(true)
    expect(delivered.reload).to have_attributes(outcome: 'failed', reason: 'number not on WhatsApp')
    expect(skipped.mark_failed!('x')).to be(false)
  end

  it 'does not make recipients searchable' do
    expect(described_class.ransackable_attributes).not_to include('recipient')
  end

  describe 'secrets in failure reasons' do
    let(:store_secret) { 'live-auth-key-must-not-leak-42' }

    it 'never stores a provider response body or a secret from a failed send' do
      create(:notification_channel_provider, :msg91_sms, store: store,
                                                         shared_secrets: { auth_key: store_secret })
      body = { 'type' => 'error', 'message' => "Invalid key #{store_secret}", 'trace' => 'x' * 500 }
      stub_provider_http(status: 401, body: body)
      message = SpreeNotificationProviders::Message.new(channel: :sms, type: :otp_code, to: '9876543210', code: '1')

      SpreeNotificationProviders.deliver(store: store, message: message)

      reason = described_class.last.reason
      expect(reason).not_to include(store_secret)
      expect(reason).not_to include('trace')
      expect(reason.length).to be < 160
    end
  end

  describe 'parameter filtering' do
    it 'filters provider secret params from logs' do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filtered = filter.filter(
        'entry' => { 'secret_settings' => { 'password' => 'p' }, 'shared_secret_settings' => { 'api_key' => 'k' } },
        'secret' => 'hook', 'code' => '123456'
      )

      expect(filtered['entry']['secret_settings']).to eq('[FILTERED]')
      expect(filtered['entry']['shared_secret_settings']).to eq('[FILTERED]')
      expect(filtered['secret']).to eq('[FILTERED]')
      expect(filtered['code']).to eq('[FILTERED]')
    end
  end
end
