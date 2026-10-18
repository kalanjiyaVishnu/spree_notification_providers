# frozen_string_literal: true

Spree::Core::Engine.add_routes do
  # Gupshup message-event callback: /webhooks/gupshup?secret=<store webhook secret>
  post 'webhooks/gupshup', to: 'webhooks/gupshup#create', as: :gupshup_webhook

  namespace :admin do
    resources :notification_providers, only: :index
    resources :notification_channel_providers, only: %i[create edit update destroy] do
      member do
        patch :position, action: :reposition
        post :test
      end
    end
    resources :notification_deliveries, only: %i[index show], param: :message_ref
  end
end
