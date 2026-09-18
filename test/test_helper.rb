ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require "webmock/minitest"

# No test ever reaches the network. Every outgoing call — starting with the
# generator microservice — is stubbed explicitly, so a missing stub fails loudly
# instead of silently hitting a real service. Localhost stays open for Capybara's
# own server and for chromedriver.
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
