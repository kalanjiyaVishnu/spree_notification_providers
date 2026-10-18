# frozen_string_literal: true

# Message types the gem itself sends. Apps register their own in an
# initializer (see README).
SpreeNotificationProviders.register_message_type :provider_test,
                                                 label: 'Test message', channels: %i[email sms whatsapp]
SpreeNotificationProviders.register_message_type :transactional_email,
                                                 label: 'Transactional email', channels: %i[email]
