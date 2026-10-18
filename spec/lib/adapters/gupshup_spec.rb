# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SpreeNotificationProviders::Adapters::Gupshup do
  let(:store) { @default_store }
  let(:adapter) { described_class.new(SpreeNotificationProviders.provider(:gupshup)) }
  let(:uuid) { 'c6aecef6-bcb0-4fb1-8100-28c094e3bc6b' }
  let(:message) do
    SpreeNotificationProviders::Message.new(channel: :whatsapp, type: :otp_code, to: '+91 98765 43210', code: '482913')
  end

  def context(template:, **settings)
    SpreeNotificationProviders::Adapters::Context.new(
      store: store, channel: :whatsapp, template: template, templates: { 'otp_code' => template },
      settings: { api_key: 'gupshup-api-key-123456', source_number: '919999999999', app_name: 'shopapp',
                  app_id: 'app-1' }.merge(settings)
    )
  end

  before { described_class.clear_template_cache(store) }

  it 'sends the template UUID directly with the code as parameter' do
    stub_provider_http(status: 202, body: { 'status' => 'submitted', 'messageId' => 'gs-1' })

    result = adapter.deliver(message, context(template: uuid))

    expect(result).to be_delivered
    expect(result.provider_message_id).to eq('gs-1')
    request = provider_http_requests.last
    expect(request[:url]).to eq("#{described_class::HOST}#{described_class::SEND_PATH}")
    expect(request[:headers]).to eq('apikey' => 'gupshup-api-key-123456')
    expect(request[:form]).to eq(
      'channel' => 'whatsapp', 'source' => '919999999999', 'destination' => '919876543210',
      'src.name' => 'shopapp', 'template' => { id: uuid, params: ['482913'] }.to_json
    )
  end

  it 'resolves a template name through the app template list and caches it' do
    with_memory_cache do
      stub_provider_http do |method, _url, _opts|
        if method == :get
          [200, { 'templates' => [{ 'id' => uuid, 'elementName' => 'verify_otp', 'status' => 'APPROVED' }] }]
        else
          [202, { 'status' => 'submitted', 'messageId' => 'gs-2' }]
        end
      end

      2.times { adapter.deliver(message, context(template: 'verify_otp')) }

      gets = provider_http_requests.select { |r| r[:method] == :get }
      expect(gets.size).to eq(1)
      expect(gets.first[:url]).to end_with('/wa/app/app-1/template')
      expect(provider_http_requests.last[:form]['template']).to include(uuid)
    end
  end

  it 'fails definitely when the named template does not exist' do
    stub_provider_http(body: { 'templates' => [] })

    result = adapter.deliver(message, context(template: 'missing'))

    expect(result).to be_failed
    expect(result.reason).to eq('template_not_found')
  end

  it 'treats a timed-out template lookup as a definite failure (nothing was sent)' do
    stub_provider_http(error: Net::ReadTimeout)

    result = adapter.deliver(message, context(template: 'verify_otp'))

    expect(result).to be_failed
    expect(result.reason).to eq('template_lookup_failed: read_timeout')
  end

  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end
end
