# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SpreeNotificationProviders::Importers::EnvImporter do
  let(:store) { @default_store }

  def import(env, dry_run: false)
    described_class.new(store, env: env, dry_run: dry_run).call
  end

  it "maps each bundled provider's env inputs and enables its channels" do
    import({ 'SMTP_HOST' => 'smtp.env.test', 'SMTP_USERNAME' => 'mailer@env.test', 'SMTP_PASSWORD' => 'env-smtp-pass-123',
             'GUPSHUP_API_KEY' => 'gs-env-key-123456' })

    smtp = Spree::NotificationChannelProvider.find_by!(store: store, provider_key: 'smtp', channel: 'email')
    expect(smtp).to have_attributes(enabled: true)
    expect(smtp.values).to include(host: 'smtp.env.test', username: 'mailer@env.test', password: 'env-smtp-pass-123')
    gupshup = Spree::NotificationChannelProvider.find_by!(store: store, provider_key: 'gupshup', channel: 'whatsapp')
    expect(gupshup.values[:api_key]).to eq('gs-env-key-123456')
    expect(Spree::NotificationChannelProvider.where(store: store, provider_key: 'msg91')).to be_empty
  end

  it 'fills blanks only and records the import source' do
    create(:notification_channel_provider, :smtp, store: store)

    writer = import({ 'SMTP_HOST' => 'smtp.other.test', 'SMTP_FROM_ADDRESS' => 'from@env.test' })

    values = Spree::NotificationChannelProvider.find_by!(store: store, provider_key: 'smtp').values
    expect(values).to include(host: 'smtp.example.com', from_address: 'from@env.test')
    expect(writer.report).to include('smtp.email.host', 'unchanged')
    config = Spree::NotificationProviderConfig.find_by!(store: store, provider_key: 'smtp')
    expect(config).to have_attributes(import_source: 'env', imported_at: be_present)
  end

  it 'saves nothing on a dry run' do
    expect { import({ 'SMTP_HOST' => 'smtp.env.test' }, dry_run: true) }
      .not_to change(Spree::NotificationChannelProvider, :count)
  end
end
