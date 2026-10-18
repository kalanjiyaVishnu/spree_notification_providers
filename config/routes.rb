# frozen_string_literal: true

Spree::Core::Engine.add_routes do
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
