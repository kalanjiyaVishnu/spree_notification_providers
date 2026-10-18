# frozen_string_literal: true

# Message types the specs use. In the host app they are registered by its
# initializer and by spree_otp_auth; a standalone run registers them here.
{
  otp_code: ['Login code', %i[email sms whatsapp], false],
  template_email: ['Email template', %i[email], false],
  back_in_stock: ['Back in stock', %i[email sms], false],
  order_notification: ['Order notification', %i[email], false],
  customer_blast: ['Customer group blast', %i[email sms], true]
}.each do |key, (label, channels, bulk)|
  next if SpreeNotificationProviders.message_type(key)

  SpreeNotificationProviders.register_message_type(key, label: label, channels: channels, bulk: bulk)
end
