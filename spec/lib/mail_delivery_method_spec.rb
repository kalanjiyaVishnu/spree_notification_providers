# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SpreeNotificationProviders::MailDeliveryMethod do
  let(:store) { @default_store }
  let(:method) { described_class.new }
  let(:mail) do
    Mail.new do
      to 'jo@example.com'
      from 'shop@example.com'
      subject 'Hello'
      body 'Hi'
    end
  end

  def result(outcome)
    SpreeNotificationProviders::DeliveryResult.new(outcome: outcome, message_ref: 'ref-1', attempts: [])
  end

  it 'routes the mail through the store from X-Spree-Store-Id with its message type' do
    other = create(:store)
    mail['X-Spree-Store-Id'] = other.id.to_s
    mail['X-Spree-Message-Type'] = 'order_notification'
    mail['X-Spree-Provider-Template-Msg91'] = 'order-tmpl'
    allow(SpreeNotificationProviders).to receive(:deliver).and_return(result(:delivered))

    method.deliver!(mail)

    expect(SpreeNotificationProviders).to have_received(:deliver) do |store:, message:|
      expect(store).to eq(other)
      expect(message).to have_attributes(channel: :email, type: :order_notification, kind: :html,
                                         to: 'jo@example.com', mail: mail)
      expect(message.template_override(:msg91)).to eq('order-tmpl')
    end
  end

  it 'uses the last value when a header was set twice' do
    first = create(:store)
    mail['X-Spree-Store-Id'] = first.id.to_s
    mail['X-Spree-Store-Id'] = store.id.to_s
    allow(SpreeNotificationProviders).to receive(:deliver).and_return(result(:delivered))

    method.deliver!(mail)

    expect(SpreeNotificationProviders).to have_received(:deliver).with(hash_including(store: store))
  end

  it 'strips its headers before sending' do
    mail['X-Spree-Store-Id'] = store.id.to_s
    mail['X-Spree-Message-Type'] = 'order_notification'
    allow(SpreeNotificationProviders).to receive(:deliver).and_return(result(:delivered))

    method.deliver!(mail)

    expect(mail.header['X-Spree-Store-Id']).to be_nil
    expect(mail.header['X-Spree-Message-Type']).to be_nil
  end

  it 'defaults to the current store and transactional_email' do
    allow(SpreeNotificationProviders).to receive(:deliver).and_return(result(:delivered))

    method.deliver!(mail)

    expect(SpreeNotificationProviders).to have_received(:deliver) do |store:, message:|
      expect(store).to eq(Spree::Store.default)
      expect(message.type).to eq(:transactional_email)
    end
  end

  it 'raises DeliveryFailed on :failed and :no_provider so the job retries' do
    allow(SpreeNotificationProviders).to receive(:deliver).and_return(result(:failed), result(:no_provider))

    expect { method.deliver!(mail) }.to raise_error(SpreeNotificationProviders::DeliveryFailed)
    expect { method.deliver!(mail) }.to raise_error(SpreeNotificationProviders::DeliveryFailed)
  end

  it 'does not raise on :unknown, so no retry can duplicate the mail' do
    allow(SpreeNotificationProviders).to receive(:deliver).and_return(result(:unknown))

    expect { method.deliver!(mail) }.not_to raise_error
  end

  it 'is registered with Action Mailer' do
    expect(ActionMailer::Base.delivery_methods).to include(spree_notification_providers: described_class)
  end
end
