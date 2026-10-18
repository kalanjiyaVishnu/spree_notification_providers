# frozen_string_literal: true

# Fakes SpreeNotificationProviders::Http for adapter and router specs.
#
#   stub_provider_http(status: 200, body: { 'type' => 'success' })
#   stub_provider_http(error: Net::ReadTimeout)
#   stub_provider_http { |method, url, opts| [200, {...}] }   # per-request
#
# Every request is recorded in `provider_http_requests` as
# { method:, url:, headers:, query:, form:, json: }.
module ProviderHttpHelpers
  FakeResponse = Struct.new(:code, :body)

  def provider_http_requests
    @provider_http_requests ||= []
  end

  def stub_provider_http(status: 200, body: {}, error: nil, &block)
    recorder = provider_http_requests
    allow(SpreeNotificationProviders::Http).to receive(:request) do |method, url, **opts|
      recorder << opts.merge(method: method, url: url)
      raise error if error

      code, payload = block ? block.call(method, url, opts) : [status, body]
      raise payload if payload.is_a?(Class) && payload <= Exception

      FakeResponse.new(code.to_s, payload.is_a?(String) ? payload : payload.to_json)
    end
  end
end

RSpec.configure do |config|
  config.include ProviderHttpHelpers

  # Bundled adapters must never reach a real provider from a spec.
  config.before do
    allow(SpreeNotificationProviders::Http).to receive(:request)
      .and_raise('Real provider HTTP call in a spec; use stub_provider_http')
  end
end

Dir[File.expand_path('../factories/**/*.rb', __dir__)].each { |file| require file }
