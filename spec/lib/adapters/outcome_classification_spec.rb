# frozen_string_literal: true

require 'rails_helper'

# Research R5: only a definite failure may move on to the next provider.
RSpec.describe 'Adapter outcome classification' do
  let(:store) { @default_store }
  let(:secret) { 'super-secret-auth-key-998877' }

  def msg91_deliver
    adapter = SpreeNotificationProviders::Adapters::Msg91.new(SpreeNotificationProviders.provider(:msg91))
    context = SpreeNotificationProviders::Adapters::Context.new(
      store: store, channel: :sms, template: 't1', templates: {}, settings: { auth_key: secret }
    )
    message = SpreeNotificationProviders::Message.new(channel: :sms, type: :otp_code, to: '9876543210', code: '1')
    adapter.deliver(message, context)
  end

  {
    Net::OpenTimeout => %i[failed connect_timeout],
    Errno::ECONNREFUSED => %i[failed connection_refused],
    SocketError => %i[failed dns_error],
    OpenSSL::SSL::SSLError => %i[failed tls_error],
    Net::ReadTimeout => %i[unknown read_timeout],
    Errno::ECONNRESET => %i[unknown connection_reset]
  }.each do |error, (outcome, reason)|
    it "classifies #{error} as #{outcome}" do
      stub_provider_http(error: error)

      result = msg91_deliver

      expect(result.outcome).to eq(outcome)
      expect(result.reason).to eq(reason.to_s)
    end
  end

  it 'treats HTTP 4xx as a definite failure with the provider message' do
    stub_provider_http(status: 401, body: { 'type' => 'error', 'message' => 'Invalid authkey' })

    result = msg91_deliver

    expect(result).to be_failed
    expect(result.reason).to eq('http_401: Invalid authkey')
  end

  it 'treats a 5xx that explains itself as a failure' do
    stub_provider_http(status: 503, body: { 'type' => 'error', 'message' => 'Service down' })

    expect(msg91_deliver).to be_failed
  end

  it 'treats a 5xx with no body as unknown' do
    stub_provider_http(status: 502, body: '')

    result = msg91_deliver

    expect(result).to be_unknown
    expect(result.reason).to eq('http_502')
  end

  it 'treats a 2xx rejection as a failure' do
    stub_provider_http(status: 200, body: { 'type' => 'error', 'message' => 'Template not approved' })

    expect(msg91_deliver.reason).to eq('rejected: Template not approved')
  end

  it 'never puts the auth key into the reason' do
    stub_provider_http(status: 401, body: { 'type' => 'error', 'message' => "bad key #{secret}" })

    expect(msg91_deliver.reason).not_to include(secret)
    expect(msg91_deliver.reason).to include('[FILTERED]')
  end

  describe 'SMTP' do
    let(:adapter) { SpreeNotificationProviders::Adapters::Smtp.new(SpreeNotificationProviders.provider(:smtp)) }
    let(:context) do
      SpreeNotificationProviders::Adapters::Context.new(
        store: store, channel: :email, template: nil, templates: {},
        settings: { host: 'h', port: 587, username: 'u', password: 'smtp-pass-123456' }
      )
    end
    let(:message) do
      SpreeNotificationProviders::Message.new(channel: :email, type: :x, to: 'a@b.co', subject: 's', html: 'x')
    end

    {
      'Net::SMTPAuthenticationError' => 'smtp_auth',
      'Net::SMTPFatalError' => 'smtp_rejected',
      'Net::SMTPServerBusy' => 'smtp_busy'
    }.each do |error_name, code|
      it "classifies #{error_name} as failed (#{code})" do
        error = error_name.constantize.new(Net::SMTP::Response.parse('535 5.7.8 auth failed smtp-pass-123456'))
        allow_any_instance_of(Mail::Message).to receive(:deliver!).and_raise(error)

        result = adapter.deliver(message, context)

        expect(result).to be_failed
        expect(result.reason).to start_with(code)
        expect(result.reason).not_to include('smtp-pass-123456')
      end
    end

    it 'classifies a read timeout during SMTP as unknown' do
      allow_any_instance_of(Mail::Message).to receive(:deliver!).and_raise(Net::ReadTimeout)

      expect(adapter.deliver(message, context)).to be_unknown
    end
  end

  describe 'Gupshup' do
    it 'treats a non-submitted reply as a failure' do
      stub_provider_http(status: 200, body: { 'status' => 'error' })
      adapter = SpreeNotificationProviders::Adapters::Gupshup.new(SpreeNotificationProviders.provider(:gupshup))
      context = SpreeNotificationProviders::Adapters::Context.new(
        store: store, channel: :whatsapp, template: 'c6aecef6-bcb0-4fb1-8100-28c094e3bc6b', templates: {},
        settings: { api_key: 'k', source_number: '919999999999', app_name: 'a' }
      )
      message = SpreeNotificationProviders::Message.new(channel: :whatsapp, type: :otp_code, to: '919876543210', code: '1')

      result = adapter.deliver(message, context)

      expect(result).to be_failed
      expect(result.reason).to eq('rejected: status error')
    end
  end
end
