require "test_helper"

# Two Stripe endpoints share /webhooks/stripe: the platform's events, and the
# designers' connected accounts' (`account.updated`). Each is signed with its
# own secret, and either must be accepted.
module Payments
  class StripeWebhookSignatureTest < ActiveSupport::TestCase
    PLATFORM = "whsec_test_platform_placeholder".freeze
    CONNECT = "whsec_test_connect_placeholder".freeze
    PAYLOAD = { id: "evt_1", object: "event", type: "account.updated", data: { object: {} } }.to_json.freeze

    setup { ENV["STRIPE_WEBHOOK_SECRET"] = PLATFORM }
    teardown { %w[ STRIPE_WEBHOOK_SECRET STRIPE_CONNECT_WEBHOOK_SECRET ].each { |k| ENV.delete(k) } }

    test "an event signed with the platform's secret is read" do
      event = StripeClient.decode_webhook(payload: PAYLOAD, signature: sign(PLATFORM))

      assert_equal "evt_1", event.id
    end

    test "an event signed with the connected accounts' secret is read too" do
      ENV["STRIPE_CONNECT_WEBHOOK_SECRET"] = CONNECT

      event = StripeClient.decode_webhook(payload: PAYLOAD, signature: sign(CONNECT))

      assert_equal "account.updated", event.type
    end

    test "without the second secret, a connected account's event is refused" do
      assert_raises(Stripe::SignatureVerificationError) do
        StripeClient.decode_webhook(payload: PAYLOAD, signature: sign(CONNECT))
      end
    end

    test "a signature from neither secret is refused" do
      ENV["STRIPE_CONNECT_WEBHOOK_SECRET"] = CONNECT

      assert_raises(Stripe::SignatureVerificationError) do
        StripeClient.decode_webhook(payload: PAYLOAD, signature: sign("whsec_someone_else"))
      end
    end

    private
      def sign(secret)
        Stripe::Webhook::Signature.generate_header(
          Time.now, Stripe::Webhook::Signature.compute_signature(Time.now, PAYLOAD, secret)
        )
      end
  end
end
