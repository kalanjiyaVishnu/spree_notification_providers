# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SpreeNotificationProviders::Adapters::Msg91 do
  let(:store) { @default_store }
  let(:definition) { SpreeNotificationProviders.provider(:msg91) }
  let(:adapter) { described_class.new(definition) }

  def context(channel, template: 'tmpl-1', **settings)
    SpreeNotificationProviders::Adapters::Context.new(
      store: store, channel: channel, template: template, templates: {},
      settings: { auth_key: 'msg91-auth-key-1234567890', default_country_code: '91' }.merge(settings)
    )
  end

  def message(**attrs)
    SpreeNotificationProviders::Message.new(**{ channel: :sms, type: :otp_code, to: '9876543210', code: '482913',
                                                expiry_minutes: 10 }.merge(attrs))
  end

  describe 'SMS OTP' do
    it 'calls the OTP API with the template, prefixed number, code, expiry and sender' do
      stub_provider_http(body: { 'type' => 'success', 'request_id' => 'req-1' })

      result = adapter.deliver(message, context(:sms, sender_id: 'SHOPID'))

      expect(result).to be_delivered
      expect(result.provider_message_id).to eq('req-1')
      request = provider_http_requests.last
      expect(request[:url]).to eq(described_class::OTP_URL)
      expect(request[:headers]).to include('authkey' => 'msg91-auth-key-1234567890')
      expect(request[:query]).to eq(template_id: 'tmpl-1', mobile: '919876543210', otp: '482913', otp_expiry: 10,
                                    sender: 'SHOPID')
    end

    it 'keeps an already international number as is' do
      stub_provider_http(body: { 'type' => 'success' })

      adapter.deliver(message(to: '+44 7700 900123'), context(:sms))

      expect(provider_http_requests.last[:query][:mobile]).to eq('447700900123')
    end
  end

  describe 'SMS template (Flow)' do
    it 'sends recipients with the variables merged in' do
      stub_provider_http(body: { 'type' => 'success', 'message' => 'flow-req-9' })
      msg = message(type: :back_in_stock, kind: :template, code: nil,
                    variables: { 'product' => 'Tee', 'url' => 'https://x.test/p' })

      result = adapter.deliver(msg, context(:sms, template: 'flow-1'))

      expect(result.provider_message_id).to eq('flow-req-9')
      request = provider_http_requests.last
      expect(request[:url]).to eq(described_class::FLOW_URL)
      expect(request[:json]).to eq(template_id: 'flow-1', short_url: '1',
                                   recipients: [{ 'mobiles' => '919876543210', 'product' => 'Tee',
                                                  'url' => 'https://x.test/p' }])
    end
  end

  describe 'WhatsApp OTP' do
    it 'uses the OTP API with whatsapp=1 and no sender' do
      stub_provider_http(body: { 'type' => 'success', 'message_id' => 'wa-1' })

      result = adapter.deliver(message(channel: :whatsapp), context(:whatsapp, sender_id: 'IGNORED'))

      expect(result.provider_message_id).to eq('wa-1')
      expect(provider_http_requests.last[:query]).to include(whatsapp: 1, template_id: 'tmpl-1')
      expect(provider_http_requests.last[:query]).not_to have_key(:sender)
    end
  end

  describe 'email template' do
    let(:email) do
      SpreeNotificationProviders::Message.new(
        channel: :email, type: :template_email, kind: :template, to: 'jo@example.com', to_name: 'Jo',
        variables: { 'NAME' => 'Jo' }, from_email: 'hello@shop.test', from_name: 'Shop', reply_to: 'help@shop.test'
      )
    end

    it 'posts the template payload with sender, domain and reply-to' do
      stub_provider_http(body: { 'status' => 'success', 'hasError' => false, 'data' => { 'unique_id' => 'em-1' } })

      result = adapter.deliver(email, context(:email, template: 'welcome', domain: 'mail.shop.test'))

      expect(result.provider_message_id).to eq('em-1')
      expect(provider_http_requests.last[:json]).to eq(
        recipients: [{ to: [{ email: 'jo@example.com', name: 'Jo' }], variables: { 'NAME' => 'Jo' } }],
        from: { name: 'Shop', email: 'hello@shop.test' },
        domain: 'shop.test', template_id: 'welcome', reply_to: [{ email: 'help@shop.test' }]
      )
    end

    it 'falls back to the default from address and its domain' do
      stub_provider_http(body: { 'status' => 'success' })
      msg = SpreeNotificationProviders::Message.new(channel: :email, type: :template_email, kind: :template,
                                                    to: 'jo@example.com')

      adapter.deliver(msg, context(:email, template: 'welcome', default_from_email: 'no-reply@mail.other.test'))

      payload = provider_http_requests.last[:json]
      expect(payload[:from]).to eq(name: store.name, email: 'no-reply@mail.other.test')
      expect(payload[:domain]).to eq('mail.other.test')
    end
  end

  describe 'bulk' do
    it 'sends one email request for the batch' do
      stub_provider_http(body: { 'status' => 'success' })
      bulk = SpreeNotificationProviders::BulkMessage.new(channel: :email, type: :customer_blast,
                                                         recipients: %w[a@x.test b@x.test], variables: { 'V' => '1' })

      expect(adapter.deliver_bulk(bulk, context(:email, template: 'blast', domain: 'x.test'))).to be_delivered
      expect(provider_http_requests.last[:json][:recipients].size).to eq(2)
    end

    it 'sends one SMS flow request for the batch' do
      stub_provider_http(body: { 'type' => 'success', 'message' => 'r' })
      bulk = SpreeNotificationProviders::BulkMessage.new(channel: :sms, type: :customer_blast,
                                                         recipients: %w[9876543210 9876543211])

      adapter.deliver_bulk(bulk, context(:sms, template: 'flow-2'))

      expect(provider_http_requests.last[:json][:recipients].map { |r| r['mobiles'] })
        .to eq(%w[919876543210 919876543211])
    end
  end
end
