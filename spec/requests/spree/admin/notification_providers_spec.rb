# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin notification providers', type: :request do
  let(:store) { @default_store }
  let(:admin) { create(:admin_user) }

  before { login_as(admin, scope: :admin_user) }
  after { Warden.test_reset! }

  describe 'GET /admin/notification_providers' do
    it 'lists the providers available for the channel tab' do
      get '/admin/notification_providers', params: { channel: 'whatsapp' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="available-gupshup"', 'id="available-msg91"')
      expect(response.body).not_to include('id="available-smtp"')
    end

    it 'shows added entries in priority order with status and missing inputs' do
      create(:notification_channel_provider, :smtp, store: store)
      create(:notification_channel_provider, store: store, channel: 'email', provider_key: 'msg91')

      get '/admin/notification_providers', params: { channel: 'email' }

      body = response.body
      expect(body.index('SMTP')).to be < body.index('MSG91')
      expect(body).to include('Missing: Auth key, Sending domain')
      expect(body).not_to include('id="available-smtp"')
    end

    it 'does not show another store\'s entries' do
      create(:notification_channel_provider, :smtp, store: create(:store))

      get '/admin/notification_providers', params: { channel: 'email' }

      expect(response.body).to include('id="available-smtp"')
    end
  end

  describe 'POST /admin/notification_channel_providers' do
    it 'adds a disabled entry at the bottom and its shared config' do
      create(:notification_channel_provider, :smtp, store: store)

      post '/admin/notification_channel_providers', params: { channel: 'email', provider_key: 'msg91' }

      entry = Spree::NotificationChannelProvider.find_by!(store: store, channel: 'email', provider_key: 'msg91')
      expect(entry).to have_attributes(enabled: false, position: 2)
      expect(Spree::NotificationProviderConfig.exists?(store: store, provider_key: 'msg91')).to be(true)
      expect(response).to redirect_to("/admin/notification_channel_providers/#{entry.to_param}/edit")
    end

    it 'refuses a provider that does not serve the channel' do
      post '/admin/notification_channel_providers', params: { channel: 'sms', provider_key: 'smtp' }

      expect(Spree::NotificationChannelProvider.count).to eq(0)
    end
  end

  describe 'editing an entry' do
    let!(:entry) { create(:notification_channel_provider, :smtp, store: store) }
    let(:path) { "/admin/notification_channel_providers/#{entry.to_param}" }

    it 'renders only this provider\'s inputs and never the secret value' do
      get "#{path}/edit"

      body = response.body
      expect(body).to include('entry[settings][host]', 'entry[secret_settings][password]')
      expect(body).not_to include('auth_key', 'source_number')
      expect(body).not_to include('smtp-test-password')
      expect(body).to include('Set ••••word')
    end

    it 'saves with missing required inputs and shows the entry as not ready' do
      patch path, params: { entry: { settings: { host: '' } } }

      expect(response).to redirect_to("#{path}/edit")
      expect(entry.reload.missing_inputs).to eq(['Host'])
      get "#{path}/edit"
      expect(response.body).to include('Missing: Host')
    end

    it 'keeps a secret on a blank submit and clears it on request' do
      patch path, params: { entry: { secret_settings: { password: '' }, settings: { host: 'smtp2.test' } } }
      expect(entry.reload.values).to include(password: 'smtp-test-password', host: 'smtp2.test')

      patch path, params: { entry: { clear_secrets: ['password'] } }
      expect(entry.reload.values[:password]).to be_nil
    end

    it 'shows field errors for malformed values' do
      patch path, params: { entry: { settings: { port: 'abc' } } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Port must be a whole number')
    end

    it 'toggles enabled from the list without touching inputs' do
      patch path, params: { entry: { enabled: '0' }, return_to: 'index' }

      expect(response).to redirect_to('/admin/notification_providers?channel=email')
      expect(entry.reload).to have_attributes(enabled: false)
      expect(entry.values[:host]).to eq('smtp.example.com')
    end

    it 'removes the entry' do
      delete path

      expect(Spree::NotificationChannelProvider.exists?(entry.id)).to be(false)
    end
  end

  describe 'shared inputs' do
    it 'enters the MSG91 auth key once for every MSG91 channel' do
      sms = create(:notification_channel_provider, store: store, channel: 'sms', provider_key: 'msg91')
      email = create(:notification_channel_provider, store: store, channel: 'email', provider_key: 'msg91')

      patch "/admin/notification_channel_providers/#{sms.to_param}",
            params: { entry: { shared_secret_settings: { auth_key: 'shared-auth-key-123456' } } }

      expect(email.reload.values[:auth_key]).to eq('shared-auth-key-123456')
      get "/admin/notification_channel_providers/#{email.to_param}/edit"
      expect(response.body).to include('Used by: Email and SMS', 'Set ••••3456')
      expect(response.body).not_to include('shared-auth-key-123456')
    end
  end

  describe 'templates' do
    it 'stores templates only for registered message types of the channel' do
      entry = create(:notification_channel_provider, :msg91_sms, store: store)

      patch "/admin/notification_channel_providers/#{entry.to_param}",
            params: { entry: { templates: { otp_code: ' tmpl-a ', bogus_type: 'x', back_in_stock: '' } } }

      expect(entry.reload.templates).to eq('otp_code' => 'tmpl-a')
    end
  end

  describe 'PATCH /admin/notification_channel_providers/:id/position' do
    it 'reorders within the store and channel only' do
      first = create(:notification_channel_provider, :smtp, store: store)
      second = create(:notification_channel_provider, :msg91_email, store: store)
      other_channel = create(:notification_channel_provider, :msg91_sms, store: store)

      patch "/admin/notification_channel_providers/#{second.to_param}/position",
            params: { notification_channel_provider: { position: 1 } }

      expect(response).to have_http_status(:no_content)
      expect([second.reload.position, first.reload.position]).to eq([1, 2])
      expect(other_channel.reload.position).to eq(1)
    end
  end

  describe 'authorization' do
    it 'requires a signed-in admin' do
      Warden.test_reset!

      get '/admin/notification_providers'

      expect(response).to have_http_status(:redirect)
      expect(response.location).not_to include('/admin/notification_providers')
    end

    it 'grants the screens through NotificationProviderManagement' do
      ability_class = Class.new { include CanCan::Ability }
      ability = ability_class.new
      Spree::PermissionSets::NotificationProviderManagement.new(ability).activate!

      expect(ability.can?(:manage, Spree::NotificationChannelProvider)).to be(true)
      expect(ability.can?(:manage, Spree::NotificationDelivery)).to be(true)
    end
  end
end
