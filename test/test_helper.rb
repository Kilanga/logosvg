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

    # Background work is how this application talks to the outside world, so
    # "which job did that enqueue?" is a question worth asking from any test,
    # not only from job tests.
    include ActiveJob::TestHelper

    # And email is how it talks to workshops: a print request that sends no
    # email has not been sent. `assert_emails` belongs everywhere too.
    include ActionMailer::TestHelper

    # Mais `ActionMailer::TestHelper` ne vide pas `deliveries` — seuls
    # `ActionMailer::TestCase` et les tests d'intégration le font. Inclus
    # partout comme ici, il laisse donc les envois d'un test visibles par le
    # suivant, et un `deliveries.find { … }` remonte l'email d'un autre test.
    # La panne intermittente par excellence : elle ne dépend que de l'ordre de
    # passage, donc du seed, donc de rien.
    setup { ActionMailer::Base.deliveries.clear }
  end
end
