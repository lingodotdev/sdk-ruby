# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv/load'
require 'rspec'
require 'sdk/ruby'

# Require all spec support files
Dir['./spec/support/**/*.rb'].sort.each { |f| require f }

# Check for required API key
unless ENV['LINGODOTDEV_API_KEY']
  raise "LINGODOTDEV_API_KEY environment variable is not set. " \
        "Please set it before running tests."
end

RSpec.configure do |config|
  # Enable color in output
  config.color = true
  config.tty = true

  # Use documentation format
  config.formatter = :documentation

  # Show slowest examples
  config.profile_examples = 10

  # Fail fast on first error in suite (remove comment to enable)
  # config.fail_fast = true

  # Only run tests matching the given filter
  # config.filter_run :focus

  # Run all tests when no filter is applied
  config.run_all_when_everything_filtered = true
end
