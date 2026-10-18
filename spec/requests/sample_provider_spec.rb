# frozen_string_literal: true

require 'rails_helper'

# SC-008: an app adds a provider with register_provider and an adapter class;
# it appears in the admin and the router with no change to gem code.
RSpec.describe 'Registering a new provider', type: :request do
  let(:store) { @default_store }
  let(:admin) { create(:admin_user) }
  let(:adapter_calls) { [] }

  before { login_as(admin, scope: :admin_user) }

  before do
    stub_const('SampleSmsAdapter', Class.new(SpreeNotificationProviders::Adapters::Base))
    log = adapter_calls
    SampleSmsAdapter.define_method(:deliver) do |message, context|
      log << { to: message.to, code: message.code, token: context[:token], from: context[:from_number],
               template: context.template }
      SpreeNotificationProviders::Result.delivered('sample-1')
    end

    SpreeNotificationProviders.register_provider :sample do
      label 'Sample SMS'
      adapter 'SampleSmsAdapter'
      shared_input :token, label: 'Token', required: true, secret: true
      channel :sms, kinds: %i[otp template], template_required: true do
        input :from_number, label: 'From number', type: :phone, required: true
      end
    end
  end

  after do
    SpreeNotificationProviders.unregister_provider(:sample)
    Warden.test_reset!
  end

  it 'is listed as available in the admin' do
    expect(SpreeNotificationProviders.providers_for(:sms).map(&:key)).to include(:sample)

    get '/admin/notification_providers', params: { channel: 'sms' }

    expect(response.body).to include('id="available-sample"', 'Sample SMS')
  end

  it 'shows only its own inputs and templates on the configure page' do
    entry = create(:notification_channel_provider, store: store, channel: 'sms', provider_key: 'sample')

    get "/admin/notification_channel_providers/#{entry.to_param}/edit"

    expect(response.body).to include('entry[shared_secret_settings][token]', 'entry[settings][from_number]',
                                     'entry[templates][otp_code]')
    expect(response.body).not_to include('auth_key', 'sender_id')
  end

  it 'saves its inputs from the admin' do
    entry = create(:notification_channel_provider, store: store, channel: 'sms', provider_key: 'sample', enabled: false)

    patch "/admin/notification_channel_providers/#{entry.to_param}", params: {
      entry: { enabled: '1', shared_secret_settings: { token: 'sample-token-123456' },
               settings: { from_number: '+14155550100' }, templates: { otp_code: 'otp-tmpl' } }
    }

    expect(entry.reload.status).to eq(:ready)
  end

  it 'is used by the router with its settings and template' do
    create(:notification_channel_provider, store: store, channel: 'sms', provider_key: 'sample',
                                           shared_secrets: { token: 'sample-token-123456' },
                                           settings: { 'from_number' => '+14155550100' },
                                           templates: { 'otp_code' => 'otp-tmpl' })
    message = SpreeNotificationProviders::Message.new(channel: :sms, type: :otp_code, to: '+919876543210', code: '4242')

    result = SpreeNotificationProviders.deliver(store: store, message: message)

    expect(result).to have_attributes(outcome: :delivered, provider_key: :sample, provider_message_id: 'sample-1')
    expect(adapter_calls).to eq([{ to: '+919876543210', code: '4242', token: 'sample-token-123456',
                                   from: '+14155550100', template: 'otp-tmpl' }])
  end
end
