# frozen_string_literal: true

SpreeNotificationProviders.register_provider :gupshup do
  label 'Gupshup'
  adapter 'SpreeNotificationProviders::Adapters::Gupshup'

  shared_input :api_key, label: 'API key', required: true, secret: true, env: 'GUPSHUP_API_KEY'
  shared_input :webhook_secret, label: 'Webhook secret', secret: true, env: 'GUPSHUP_WEBHOOK_SECRET',
                                help: 'Random string in the callback URL: /webhooks/gupshup?secret=<this value>.'

  channel :whatsapp, kinds: %i[otp template], template_required: true do
    input :source_number, label: 'Source number', type: :phone, required: true, format: /\A[1-9]\d{9,14}\z/,
                          help: 'Your WhatsApp business number with country code, digits only.'
    input :app_name, label: 'App name', required: true
    input :app_id, label: 'App ID', help: 'Needed when a template is entered by name instead of its UUID.'

    # A template entered by name is resolved through the app's template list,
    # which needs the app ID.
    missing_check do |values, templates|
      named = templates.values.any? do |template|
        template.present? && !template.to_s.match?(SpreeNotificationProviders::Adapters::Gupshup::UUID_FORMAT)
      end
      named && values[:app_id].blank? ? ['App ID'] : []
    end
  end
end
