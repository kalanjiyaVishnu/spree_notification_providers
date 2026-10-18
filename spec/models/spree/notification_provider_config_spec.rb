# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::NotificationProviderConfig do
  let(:store) { @default_store }

  it 'encrypts shared secrets and reads them back' do
    config = create(:notification_provider_config, store: store, provider_key: 'gupshup',
                                                   secrets: { api_key: 'gupshup-key-abcdef123456' })

    raw = described_class.connection.select_value(
      "SELECT secret_settings FROM spree_notification_provider_configs WHERE id = #{config.id}"
    )
    expect(raw).not_to include('gupshup-key-abcdef123456')
    api_key = config.shared_inputs.find { |input| input.name == :api_key }
    expect(config.reload.raw_value(api_key)).to eq('gupshup-key-abcdef123456')
  end

  it 'is unique per store and provider' do
    create(:notification_provider_config, store: store, provider_key: 'msg91')

    expect(build(:notification_provider_config, store: store, provider_key: 'msg91')).not_to be_valid
  end

  it 'has no definition once the provider is unregistered' do
    config = create(:notification_provider_config, store: store, provider_key: 'msg91')
    config.update_column(:provider_key, 'gone')

    expect(config.reload.definition).to be_nil
    expect(config.shared_inputs).to eq([])
  end
end
