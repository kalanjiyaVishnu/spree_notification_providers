# frozen_string_literal: true

# Inside the host app these specs run through the host's rails_helper (it
# globs engines/*/spec). Standalone (`bundle exec rake test_app && bundle exec
# rspec` in this directory) they run against spec/dummy.
host_helper = File.expand_path('../../../spec/rails_helper.rb', __dir__)
if File.exist?(host_helper) && !File.directory?(File.expand_path('dummy', __dir__))
  require host_helper
else
  require File.expand_path('rails_helper', __dir__)
end
