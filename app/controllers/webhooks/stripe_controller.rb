module Webhooks
  # Stripe's own callbacks.
  #
  # Not a visitor: no session, no CSRF token, no Pundit. The signature is the
  # authentication, and it is checked before the payload is read as anything
  # but bytes.
  class StripeController < ActionController::Base
    # There is no signed-in user to authorize and no records to scope. Both
    # after-actions come from ApplicationController, which this deliberately
    # does not inherit from.
    skip_forgery_protection

    def create
      event = Payments::StripeClient.decode_webhook(
        payload: request.body.read, signature: request.headers["Stripe-Signature"]
      )

      # Handled inline rather than in a job: the work is small, and Stripe's
      # own retry is a better safety net than a queue we would have to watch.
      Payments::HandleWebhook.call(event: event.to_hash)

      head :ok
    rescue Stripe::SignatureVerificationError, JSON::ParserError => e
      # Not from Stripe, or tampered with on the way. Nothing is read, nothing
      # is answered beyond "no".
      Rails.logger.warn("[stripe] refused a webhook: #{e.class}")
      head :bad_request
    rescue Payments::StripeClient::NotConfigured
      Rails.logger.error("[stripe] a webhook arrived but no signing secret is set")
      head :service_unavailable
    rescue StandardError => e
      # A 500 is what makes Stripe try again, which is exactly what we want
      # when our own side is at fault.
      Rails.logger.error("[stripe] #{e.class}: #{e.message}")
      head :internal_server_error
    end
  end
end
