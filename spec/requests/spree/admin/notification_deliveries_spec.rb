# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin delivery log', type: :request do
  let(:store) { @default_store }
  let(:admin) { create(:admin_user) }

  before { login_as(admin, scope: :admin_user) }
  after { Warden.test_reset! }

  it 'groups attempts of one message and masks the recipient' do
    ref = SecureRandom.uuid
    create(:notification_delivery, store: store, message_ref: ref, provider_key: 'smtp', outcome: 'failed',
                                   reason: 'smtp_auth', recipient: 'karthik@gmail.com', attempt_number: 1)
    create(:notification_delivery, store: store, message_ref: ref, provider_key: 'msg91', outcome: 'delivered',
                                   recipient: 'karthik@gmail.com', attempt_number: 2)

    get '/admin/notification_deliveries', params: { q: { channel_eq: 'email' } }

    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body.scan(%r{id="delivery-#{ref}"}).size).to eq(1)
    expect(body).to include('ka•••@gmail.com', 'smtp_auth', 'SMTP', 'MSG91')
    expect(body).not_to include('karthik@gmail.com')
  end

  it 'masks phone numbers' do
    create(:notification_delivery, store: store, channel: 'sms', recipient: '+919876543210', provider_key: 'msg91')

    get '/admin/notification_deliveries'

    expect(response.body).to include('+91•••••3210')
    expect(response.body).not_to include('9876543210')
  end

  it 'filters by outcome, provider, type and bulk' do
    create(:notification_delivery, store: store, outcome: 'failed', provider_key: 'smtp', recipient: 'aa@x.test')
    create(:notification_delivery, store: store, outcome: 'delivered', provider_key: 'msg91', recipient: 'bb@x.test')
    create(:notification_delivery, store: store, outcome: 'failed', bulk: true, message_type: 'customer_blast',
                                   provider_key: 'msg91', recipient: 'cc@x.test')

    get '/admin/notification_deliveries', params: { q: { outcome_eq: 'failed', provider_key_eq: 'smtp' } }
    expect(response.body).to include('aa•••@x.test')
    expect(response.body).not_to include('bb•••@x.test')

    get '/admin/notification_deliveries', params: { q: { bulk_eq: 'true' } }
    expect(response.body).to include('1 recipients')
    expect(response.body).not_to include('aa•••@x.test')
  end

  it 'filters by date range' do
    create(:notification_delivery, store: store, recipient: 'old@x.test', created_at: 10.days.ago)
    create(:notification_delivery, store: store, recipient: 'new@x.test')

    get '/admin/notification_deliveries', params: { q: { created_at_gteq: 2.days.ago.to_date.to_s } }

    expect(response.body).to include('ne•••@x.test')
    expect(response.body).not_to include('ol•••@x.test')
  end

  it 'shows newest first' do
    create(:notification_delivery, store: store, recipient: 'first@x.test', created_at: 2.hours.ago)
    create(:notification_delivery, store: store, recipient: 'second@x.test', created_at: 1.hour.ago)

    get '/admin/notification_deliveries'

    expect(response.body.index('se•••@x.test')).to be < response.body.index('fi•••@x.test')
  end

  it 'does not show another store\'s rows' do
    create(:notification_delivery, store: create(:store), recipient: 'other@x.test')

    get '/admin/notification_deliveries'

    expect(response.body).not_to include('ot•••@x.test')
  end

  it 'shows every attempt of one message' do
    ref = SecureRandom.uuid
    create(:notification_delivery, store: store, message_ref: ref, provider_key: 'smtp', outcome: 'failed', attempt_number: 1)
    create(:notification_delivery, store: store, message_ref: ref, provider_key: 'msg91', attempt_number: 2)

    get "/admin/notification_deliveries/#{ref}"

    expect(response).to have_http_status(:ok)
    expect(response.body.scan('<tr id="ndel_').size).to eq(2)
  end

  it '404s for another store\'s message' do
    delivery = create(:notification_delivery, store: create(:store))

    get "/admin/notification_deliveries/#{delivery.message_ref}"

    expect(response).to have_http_status(:not_found)
  end
end
