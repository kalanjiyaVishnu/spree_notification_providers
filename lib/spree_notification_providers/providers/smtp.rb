# frozen_string_literal: true

SpreeNotificationProviders.register_provider :smtp do
  label 'SMTP'
  adapter 'SpreeNotificationProviders::Adapters::Smtp'

  channel :email, kinds: %i[html] do
    input :host, label: 'Host', required: true, env: 'SMTP_HOST'
    input :port, label: 'Port', type: :integer, required: true, default: '587', env: 'SMTP_PORT'
    input :username, label: 'Username', required: true, env: 'SMTP_USERNAME'
    input :password, label: 'Password', required: true, secret: true, env: 'SMTP_PASSWORD'
    input :from_address, label: 'From address', type: :email, env: 'SMTP_FROM_ADDRESS',
                         help: 'Used when the message has no sender of its own.'
    input :authentication, label: 'Authentication', type: :select, options: %w[plain login cram_md5],
                           default: 'plain'
    input :starttls, label: 'Use STARTTLS', type: :boolean, default: 'true'
  end
end
