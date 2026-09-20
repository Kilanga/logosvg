module Payments
  # Sends a designer through Stripe's own onboarding, and brings back what it
  # decided.
  #
  # The platform never sees an identity document or a bank detail: Connect
  # Express hosts the whole thing, and what comes back is a single boolean —
  # whether Stripe will pay this person. Nothing is ever assigned to a designer
  # for whom it is false.
  class ConnectOnboarding
    Result = Data.define(:url, :error) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(profile:, return_url:, refresh_url:)
      @profile = profile
      @return_url = return_url
      @refresh_url = refresh_url
    end

    def call
      return failure(:not_configured) unless StripeClient.configured?

      client = StripeClient.new
      account_id = @profile.stripe_account_id.presence || create_account(client)

      link = client.create_account_link(
        account: account_id, return_url: @return_url, refresh_url: @refresh_url
      )

      @profile.update!(onboarding_started_at: Time.current)
      Result.new(url: link.url, error: nil)
    rescue StripeClient::NotConfigured
      failure(:not_configured)
    rescue StripeClient::Failed => e
      Rails.logger.error("[stripe] #{e.message}")
      failure(:unavailable)
    end

    private
      def failure(reason) = Result.new(url: nil, error: I18n.t("designers.errors.#{reason}"))

      # Created once and kept, even if the designer abandons halfway: coming
      # back must resume the same account, not open a second one.
      def create_account(client)
        account = client.create_connect_account(email: @profile.user.email_address)
        @profile.update!(stripe_account_id: account.id)
        account.id
      end
  end
end
