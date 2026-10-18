# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SpreeNotificationProviders::Adapters::Smtp do
  let(:store) { @default_store }
  let(:adapter) { described_class.new(SpreeNotificationProviders.provider(:smtp)) }
  let(:settings) do
    { host: 'smtp.shop.test', port: 2525, username: 'mailer', password: 'smtp-secret-password',
      from_address: 'fallback@shop.test', authentication: 'login', starttls: true }
  end
  let(:context) do
    SpreeNotificationProviders::Adapters::Context.new(store: store, channel: :email, settings: settings,
                                                      template: nil, templates: {})
  end
  let(:delivered) { [] }

  before do
    sent = delivered
    allow_any_instance_of(Mail::Message).to receive(:deliver!) do |mail|
      sent << mail
      mail
    end
  end

  it 'sends a built message with the store SMTP settings' do
    msg = SpreeNotificationProviders::Message.new(channel: :email, type: :transactional_email, to: 'jo@example.com',
                                                  subject: 'Hello', html: '<p>Hi</p>', from_email: 'shop@shop.test',
                                                  from_name: 'Shop', reply_to: 'help@shop.test')

    result = adapter.deliver(msg, context)

    expect(result).to be_delivered
    mail = delivered.last
    expect(mail.to).to eq(['jo@example.com'])
    expect(mail[:from].value).to eq('Shop <shop@shop.test>')
    expect(mail.reply_to).to eq(['help@shop.test'])
    expect(mail.html_part.body.to_s).to include('<p>Hi</p>')
    expect(mail.delivery_method.settings).to include(address: 'smtp.shop.test', port: 2525, user_name: 'mailer',
                                                     password: 'smtp-secret-password', authentication: :login,
                                                     enable_starttls_auto: true)
  end

  it 'sends a ready Mail::Message and keeps its own from' do
    mail = Mail.new(to: 'jo@example.com', from: 'orders@shop.test', subject: 'Order', body: 'x')
    msg = SpreeNotificationProviders::Message.new(channel: :email, type: :transactional_email, to: 'jo@example.com',
                                                  mail: mail)

    adapter.deliver(msg, context)

    expect(delivered.last.from).to eq(['orders@shop.test'])
  end

  it 'uses the from address input only when the message has no sender' do
    mail = Mail.new(to: 'jo@example.com', subject: 'Order', body: 'x')
    msg = SpreeNotificationProviders::Message.new(channel: :email, type: :transactional_email, to: 'jo@example.com',
                                                  mail: mail)

    adapter.deliver(msg, context)

    expect(delivered.last.from).to eq(['fallback@shop.test'])
  end

  it 'does not change the global Action Mailer delivery method' do
    expect do
      adapter.deliver(SpreeNotificationProviders::Message.new(channel: :email, type: :x, to: 'a@b.co', html: 'x'),
                      context)
    end.not_to(change { ActionMailer::Base.delivery_method })
  end
end
