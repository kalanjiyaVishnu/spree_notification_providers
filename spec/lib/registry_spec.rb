# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SpreeNotificationProviders::Registry do
  subject(:registry) { described_class.new }

  let(:definition_block) do
    proc do
      label 'Sample'
      adapter 'SpreeNotificationProviders::Adapters::Log'
      shared_input :token, required: true, secret: true
      channel :sms, kinds: %i[otp template] do
        input :from_number, type: :phone, required: true
      end
    end
  end

  it 'registers a provider with shared and channel inputs' do
    registry.register_provider(:sample, &definition_block)

    provider = registry.provider(:sample)
    expect(provider.label).to eq('Sample')
    expect(provider.shared_inputs.map(&:name)).to eq([:token])
    expect(provider.capability(:sms).inputs.map(&:name)).to eq([:from_number])
    expect(registry.providers_for(:sms)).to include(provider)
    expect(registry.providers_for(:email)).not_to include(provider)
  end

  it 'refuses a duplicate key unless replace: true' do
    registry.register_provider(:sample, &definition_block)

    expect { registry.register_provider(:sample, &definition_block) }
      .to raise_error(SpreeNotificationProviders::DuplicateProvider)
    expect { registry.register_provider(:sample, replace: true, &definition_block) }.not_to raise_error
  end

  it 'refuses a channel outside email, sms and whatsapp' do
    expect do
      registry.register_provider(:bad) do
        adapter 'SpreeNotificationProviders::Adapters::Log'
        channel :pigeon, kinds: %i[otp]
      end
    end.to raise_error(SpreeNotificationProviders::UnknownChannel)
  end

  it 'refuses a provider without an adapter' do
    expect { registry.register_provider(:bad) { label 'No adapter' } }.to raise_error(ArgumentError)
  end

  it 'lists message types per channel and replaces a re-registered type' do
    registry.register_message_type(:otp_code, label: 'Login code', channels: %i[sms whatsapp])
    registry.register_message_type(:otp_code, label: 'Login code', channels: %i[sms whatsapp email])

    expect(registry.message_types_for(:email).map(&:key)).to eq([:otp_code])
    expect(registry.message_types.size).to eq(1)
  end

  it 'resolves message stores through registered resolvers in order' do
    store = Spree::Store.new(name: 'X')
    registry.register_message_resolver(:gupshup) { |_id| nil }
    registry.register_message_resolver(:gupshup) { |id| store if id == 'abc' }

    expect(registry.resolve_message_store(:gupshup, 'abc')).to eq(store)
    expect(registry.resolve_message_store(:gupshup, 'zzz')).to be_nil
  end

  describe 'bundled providers' do
    it 'registers MSG91, SMTP, Gupshup and (outside production) Log' do
      keys = SpreeNotificationProviders.providers.map(&:key)
      expect(keys).to include(:msg91, :smtp, :gupshup, :log)
      expect(SpreeNotificationProviders.provider(:msg91).channel_names).to eq(%i[email sms whatsapp])
    end
  end
end
