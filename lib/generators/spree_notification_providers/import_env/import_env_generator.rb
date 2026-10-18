# frozen_string_literal: true

require 'rails/generators'

module SpreeNotificationProviders
  module Generators
    # Copies provider environment variables (MSG91_AUTH_KEY, SMTP_HOST, ...)
    # into a store's provider settings. Fills blanks only; safe to rerun.
    class ImportEnvGenerator < Rails::Generators::Base
      desc "Import provider settings from environment variables into a store's configuration"

      class_option :store, type: :string, desc: 'Store code (default: the default store)'
      class_option :dry_run, type: :boolean, default: false, desc: 'Print the report without saving'

      def import
        store = options[:store].present? ? Spree::Store.find_by!(code: options[:store]) : Spree::Store.default
        writer = SpreeNotificationProviders::Importers::EnvImporter.new(store, dry_run: options[:dry_run]).call
        say writer.report
        say(options[:dry_run] ? 'Dry run: nothing saved.' : 'Saved.')
      end
    end
  end
end
