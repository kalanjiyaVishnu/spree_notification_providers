# frozen_string_literal: true

SpreeNotificationProviders.register_provider :msg91 do
  label 'MSG91'
  adapter 'SpreeNotificationProviders::Adapters::Msg91'

  shared_input :auth_key, label: 'Auth key', required: true, secret: true, env: 'MSG91_AUTH_KEY',
                          help: 'MSG91 dashboard → Authkey. Used by every MSG91 channel.'

  channel :email, kinds: %i[template bulk], template_required: true do
    input :domain, label: 'Sending domain', required: true, env: 'MSG91_EMAIL_DOMAIN',
                   help: 'The domain verified in MSG91 Email, e.g. mail.example.com.'
    input :default_from_email, label: 'Default from address', type: :email, env: 'MSG91_EMAIL_FROM',
                               help: 'Used when the message has no sender of its own.'
  end

  channel :sms, kinds: %i[otp template bulk], template_required: true do
    input :sender_id, label: 'Sender ID', env: 'MSG91_SENDER_ID', help: 'DLT-registered 6-character sender ID.'
    input :default_country_code, label: 'Default country code', type: :integer, default: '91',
                                 help: 'Added to 10-digit numbers.'
  end

  channel :whatsapp, kinds: %i[otp], template_required: true do
    input :default_country_code, label: 'Default country code', type: :integer, default: '91',
                                 help: 'Added to 10-digit numbers.'
  end
end
