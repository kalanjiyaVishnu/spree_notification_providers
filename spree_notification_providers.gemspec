# frozen_string_literal: true

require_relative 'lib/spree_notification_providers/version'

Gem::Specification.new do |spec|
  spec.name        = 'spree_notification_providers'
  spec.version     = SpreeNotificationProviders::VERSION
  spec.authors     = ['ONTODI']
  spec.summary     = 'Per-channel notification providers with priority and failover for Spree Commerce'
  spec.description = <<~DESC.strip
    Lets each store configure Email, SMS and WhatsApp providers (MSG91, SMTP, Gupshup or your own),
    enter only the inputs each provider needs, and rank them by priority. Messages fail over to the
    next provider on definite failures only, every attempt is recorded in an admin Delivery log, and
    secrets are stored encrypted. Ships an Action Mailer delivery method so existing mailers route
    through the same priority list.
  DESC
  spec.license = 'BSD-3-Clause'

  spec.required_ruby_version = '>= 3.3'

  spec.files = Dir[
    '{app,config,db,lib}/**/*',
    'README.md',
    'CHANGELOG.md',
    'LICENSE',
    'spree_notification_providers.gemspec'
  ]
  spec.require_paths = ['lib']

  spec.add_dependency 'acts_as_list', '>= 1.0'
  spec.add_dependency 'pagy', '>= 43.0'
  spec.add_dependency 'rails', '>= 8.0'
  spec.add_dependency 'ransack', '>= 4.0'
  spec.add_dependency 'spree_admin', '>= 5.5'
  spec.add_dependency 'spree_core', '>= 5.5'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
