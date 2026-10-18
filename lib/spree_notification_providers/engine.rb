# frozen_string_literal: true

module SpreeNotificationProviders
  class Engine < ::Rails::Engine
    engine_name 'spree_notification_providers'

    config.generators do |g|
      g.test_framework :rspec
    end

    # Secrets arrive in these params; keep them out of the log lines even in
    # apps that trimmed Rails' default filter list.
    initializer 'spree_notification_providers.filter_parameters' do |app|
      app.config.filter_parameters += %i[secret_settings shared_secret_settings secret]
    end

    initializer 'spree_notification_providers.mail_delivery_method' do
      ActiveSupport.on_load(:action_mailer) do
        add_delivery_method :spree_notification_providers, SpreeNotificationProviders::MailDeliveryMethod
      end
    end

    # After the app's initializers, so `enable_log_provider` set there counts.
    config.after_initialize do
      SpreeNotificationProviders.register_log_provider! if SpreeNotificationProviders.configuration.enable_log_provider
      SpreeNotificationProviders.register_admin_navigation!
    end

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end

    config.to_prepare(&method(:activate).to_proc)
  end

  def self.register_admin_navigation!
    return unless Spree.respond_to?(:admin) && Spree.admin.respond_to?(:navigation)

    nav = Spree.admin.navigation
    nav.settings.add :notification_providers,
                     label: :notification_providers,
                     icon: 'send',
                     url: :admin_notification_providers_path,
                     position: 76,
                     active: -> { controller_path.in?(%w[spree/admin/notification_providers spree/admin/notification_channel_providers]) },
                     if: -> { can?(:manage, Spree::NotificationChannelProvider) }
    nav.settings.add :notification_deliveries,
                     label: :notification_deliveries,
                     icon: 'list-check',
                     url: :admin_notification_deliveries_path,
                     position: 77,
                     active: -> { controller_path == 'spree/admin/notification_deliveries' },
                     if: -> { can?(:manage, Spree::NotificationDelivery) }
  end
end
