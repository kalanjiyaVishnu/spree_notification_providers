# frozen_string_literal: true

FactoryBot.define do
  factory :notification_provider_config, class: 'Spree::NotificationProviderConfig' do
    store { Spree::Store.default || association(:store) }
    provider_key { 'msg91' }
    settings { {} }

    transient do
      secrets { {} }
    end

    after(:build) do |config, evaluator|
      config.secret_settings = evaluator.secrets.stringify_keys.to_json if evaluator.secrets.present?
    end
  end

  factory :notification_channel_provider, class: 'Spree::NotificationChannelProvider' do
    store { Spree::Store.default || association(:store) }
    channel { 'sms' }
    provider_key { 'msg91' }
    enabled { true }
    settings { {} }
    templates { {} }

    transient do
      secrets { {} }
      shared { {} }
      shared_secrets { {} }
    end

    after(:build) do |entry, evaluator|
      entry.secret_settings = evaluator.secrets.stringify_keys.to_json if evaluator.secrets.present?
      if evaluator.shared.present? || evaluator.shared_secrets.present?
        config = Spree::NotificationProviderConfig.find_or_initialize_by(store_id: entry.store.id,
                                                                         provider_key: entry.provider_key)
        config.settings = config.plain_values.merge(evaluator.shared.stringify_keys)
        if evaluator.shared_secrets.present?
          config.secret_settings = config.secret_values.merge(evaluator.shared_secrets.stringify_keys).to_json
        end
        config.save!
      end
    end

    # MSG91 SMS, ready to send OTPs.
    trait :msg91_sms do
      channel { 'sms' }
      provider_key { 'msg91' }
      shared_secrets { { auth_key: 'msg91-test-auth-key-123456' } }
      templates { { 'otp_code' => 'otp-template-1' } }
    end

    trait :msg91_email do
      channel { 'email' }
      provider_key { 'msg91' }
      shared_secrets { { auth_key: 'msg91-test-auth-key-123456' } }
      settings { { 'domain' => 'mail.example.com', 'default_from_email' => 'no-reply@mail.example.com' } }
      templates { { 'template_email' => 'msg91-email-template' } }
    end

    trait :smtp do
      channel { 'email' }
      provider_key { 'smtp' }
      settings { { 'host' => 'smtp.example.com', 'port' => '587', 'username' => 'mailer@example.com' } }
      secrets { { password: 'smtp-test-password' } }
    end

    trait :gupshup do
      channel { 'whatsapp' }
      provider_key { 'gupshup' }
      shared_secrets { { api_key: 'gupshup-test-api-key-1234', webhook_secret: 'hook-secret-abcdef' } }
      settings { { 'source_number' => '919876543210', 'app_name' => 'shopapp', 'app_id' => 'app-123' } }
      templates { { 'otp_code' => 'c6aecef6-bcb0-4fb1-8100-28c094e3bc6b' } }
    end

    trait :log do
      provider_key { 'log' }
    end
  end

  factory :notification_delivery, class: 'Spree::NotificationDelivery' do
    store { Spree::Store.default || association(:store) }
    message_ref { SecureRandom.uuid }
    channel { 'email' }
    provider_key { 'smtp' }
    message_type { 'transactional_email' }
    recipient { 'customer@example.com' }
    outcome { 'delivered' }
    attempt_number { 1 }
  end
end
