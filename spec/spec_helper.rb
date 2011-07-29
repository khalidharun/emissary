require 'rubygems'
require 'bundler'
require 'rspec'
require 'emissary/errors'

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/../lib')

module ExitCodeMatchers
  RSpec::Matchers.define :exit_with_code do |code|
    actual = nil
    match do |block|
      begin
        block.call
      rescue SystemExit => e
        actual = e.status
      end
      actual and actual == code
    end
    failure_message_for_should do |block|
      "expected block to call exit(#{code}) but exit" +
        (actual.nil? ? " not called" : "(#{actual}) was called")
    end
    failure_message_for_should_not do |block|
      "expected block not to call exit(#{code})"
    end
    description do
      "expect block to call exit(#{code})"
    end
  end
end

RSpec.configure do |config|
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true
  config.filter_run_excluding :exclude => true

  config.mock_with :rspec

  config.include(ExitCodeMatchers)

#  config.before(:suite) do
#    DatabaseCleaner.strategy = :truncation
#    DatabaseCleaner.clean
#  end
#
#  config.after(:each) do
#    DatabaseCleaner.clean
#  end
end
