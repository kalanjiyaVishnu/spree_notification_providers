# frozen_string_literal: true

require 'rails/generators'

module SpreeNotificationProviders
  module Generators
    class InstallGenerator < Rails::Generators::Base
      desc 'Install spree_notification_providers migrations and initializer'
      source_root File.expand_path('templates', __dir__)

      class_option :migrate, type: :boolean, default: true, banner: 'Run migrations'

      def add_initializer
        template 'initializer.rb', 'config/initializers/spree_notification_providers.rb'
      end

      def add_migrations
        run 'bundle exec rake railties:install:migrations FROM=spree_notification_providers'
      end

      def run_migrations
        if options[:migrate]
          run 'bundle exec rake db:migrate'
        else
          say_status :skipping, 'db:migrate, remember to run migrations manually'
        end
      end

      def show_next_steps
        say <<~TEXT

          spree_notification_providers is installed. Next:
            1. Add Spree::PermissionSets::NotificationProviderManagement to non-super-user admin roles.
            2. Set config.action_mailer.delivery_method = :spree_notification_providers to route mailers.
            3. Schedule Spree::NotificationDeliveries::PurgeJob daily.
            4. Admin -> Settings -> Notification providers to add providers.
        TEXT
      end
    end
  end
end
