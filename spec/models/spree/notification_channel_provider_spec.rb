# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::NotificationChannelProvider do
  let(:store) { @default_store }

  describe 'readiness' do
    it 'lists missing required shared and channel inputs by label' do
      entry = create(:notification_channel_provider, store: store, channel: 'whatsapp', provider_key: 'gupshup')

      expect(entry.missing_inputs).to contain_exactly('API key', 'Source number', 'App name')
      expect(entry.status).to eq(:not_ready)
      expect(entry).not_to be_ready
    end

    it 'is ready once required inputs are present' do
      entry = create(:notification_channel_provider, :gupshup, store: store)

      expect(entry.missing_inputs).to be_empty
      expect(entry.status).to eq(:ready)
      expect(entry.ready_for?(:otp_code)).to be(true)
    end

    it 'needs a template for template-based providers' do
      entry = create(:notification_channel_provider, :msg91_sms, store: store, templates: {})

      expect(entry).to be_ready
      expect(entry.ready_for?(:otp_code)).to be(false)
      expect(entry.skip_reason_for(nil, message_type: :otp_code)).to eq('no_template')
    end

    it 'asks for the Gupshup app ID when a template is given by name' do
      entry = create(:notification_channel_provider, :gupshup, store: store,
                                                               settings: { 'source_number' => '919876543210', 'app_name' => 'shopapp' },
                                                               templates: { 'otp_code' => 'verify_otp' })

      expect(entry.missing_inputs).to eq(['App ID'])
    end

    it 'is disabled when switched off and unavailable when the provider is gone' do
      entry = create(:notification_channel_provider, :gupshup, store: store, enabled: false)
      expect(entry.status).to eq(:disabled)

      entry.update_column(:provider_key, 'retired_provider')
      expect(entry.reload.status).to eq(:unavailable)
      expect(entry.skip_reason_for(nil, message_type: :otp_code)).to eq('unavailable')
    end

    it 'skips a message kind the provider cannot send' do
      entry = create(:notification_channel_provider, :msg91_email, store: store)
      html = SpreeNotificationProviders::Message.new(channel: :email, type: :transactional_email, to: 'a@b.co',
                                                     subject: 'Hi', html: '<p>Hi</p>')

      expect(entry.skip_reason_for(html)).to eq('unsupported')
    end

    it 'sends an HTML email carrying its own MSG91 template as that template' do
      entry = create(:notification_channel_provider, :msg91_email, store: store)
      html = SpreeNotificationProviders::Message.new(channel: :email, type: :transactional_email, to: 'a@b.co',
                                                     html: '<p>Hi</p>', templates: { msg91: 'tmpl-9' })

      expect(entry.skip_reason_for(html)).to be_nil
      expect(entry.template_for(html.type, html)).to eq('tmpl-9')
    end
  end

  describe 'inputs' do
    it 'shares provider-level inputs across channels' do
      sms = create(:notification_channel_provider, :msg91_sms, store: store)
      email = create(:notification_channel_provider, store: store, channel: 'email', provider_key: 'msg91')

      expect(email.values[:auth_key]).to eq('msg91-test-auth-key-123456')
      expect(sms.shared_with_channels).to contain_exactly('email', 'sms')
    end

    it 'stores secrets encrypted at rest' do
      entry = create(:notification_channel_provider, :smtp, store: store)

      raw = described_class.connection.select_value(
        "SELECT secret_settings FROM spree_notification_channel_providers WHERE id = #{entry.id}"
      )
      expect(raw).not_to include('smtp-test-password')
      expect(entry.reload.values[:password]).to eq('smtp-test-password')
    end

    it 'keeps a secret on a blank submit and removes it when cleared' do
      entry = create(:notification_channel_provider, :smtp, store: store)
      password = entry.channel_inputs.find { |input| input.name == :password }

      entry.assign_inputs(entry.channel_inputs, values: { 'host' => 'smtp2.example.com' }, secrets: { 'password' => '' })
      expect(entry.raw_value(password)).to eq('smtp-test-password')
      expect(entry.plain_values['host']).to eq('smtp2.example.com')

      entry.assign_inputs(entry.channel_inputs, clear: ['password'])
      expect(entry.raw_value(password)).to be_nil
    end

    it 'applies defaults and casts types' do
      entry = create(:notification_channel_provider, :smtp, store: store, settings: { 'host' => 'h', 'username' => 'u' })

      expect(entry.values).to include(port: 587, authentication: 'plain', starttls: true)
    end

    it 'rejects malformed input values on save' do
      entry = build(:notification_channel_provider, :gupshup, store: store,
                                                              settings: { 'source_number' => 'not-a-number', 'app_name' => 'x' })

      expect(entry).not_to be_valid
      expect(entry.input_errors).to have_key('source_number')
    end

    it 'rejects a provider that does not support the channel' do
      entry = build(:notification_channel_provider, store: store, channel: 'sms', provider_key: 'smtp')

      expect(entry).not_to be_valid
      expect(entry.errors[:channel]).to be_present
    end
  end

  describe 'positions' do
    it 'orders entries per store and channel' do
      other_store = create(:store)
      first = create(:notification_channel_provider, :smtp, store: store)
      second = create(:notification_channel_provider, :msg91_email, store: store)
      elsewhere = create(:notification_channel_provider, :smtp, store: other_store)
      sms = create(:notification_channel_provider, :msg91_sms, store: store)

      expect([first.position, second.position]).to eq([1, 2])
      expect(elsewhere.position).to eq(1)
      expect(sms.position).to eq(1)
    end
  end
end
