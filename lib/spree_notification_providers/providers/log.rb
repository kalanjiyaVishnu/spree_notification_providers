# frozen_string_literal: true

module SpreeNotificationProviders
  # The Log provider is registered after the app's initializers have run, so
  # `config.enable_log_provider` set there is respected.
  def self.register_log_provider!
    register_provider :log, replace: true do
      label 'Log only (development)'
      adapter 'SpreeNotificationProviders::Adapters::Log'

      %i[email sms whatsapp].each do |name|
        channel name, kinds: %i[otp template html bulk]
      end
    end
  end
end
