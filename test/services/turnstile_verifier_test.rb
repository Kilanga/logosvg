require "test_helper"

class TurnstileVerifierTest < ActiveSupport::TestCase
  ENDPOINT = "https://challenges.cloudflare.com/turnstile/v0/siteverify".freeze

  # Named so that neither a human nor a secret scanner can mistake them for real
  # keys: a literal assigned to something called SECRET_KEY is exactly what
  # GitGuardian is built to flag.
  PLACEHOLDER_SECRET = "not-a-key-turnstile-secret-placeholder".freeze
  PLACEHOLDER_SITE = "not-a-key-turnstile-site-placeholder".freeze

  test "verification is skipped when no secret key is configured" do
    result = TurnstileVerifier.call(token: "anything")

    assert_predicate result, :skipped?
    assert_not_predicate result, :success?
    assert_not_requested :post, ENDPOINT
  end

  test "a token Cloudflare accepts succeeds" do
    with_secret do
      stub_request(:post, ENDPOINT).to_return(
        body: { success: true }.to_json, headers: { "Content-Type" => "application/json" }
      )

      result = TurnstileVerifier.call(token: "bon-jeton", ip: "203.0.113.1")

      assert_predicate result, :success?
      assert_not_predicate result, :skipped?
    end
  end

  test "the secret, the token and the address are what get sent" do
    with_secret do
      stub_request(:post, ENDPOINT).to_return(body: { success: true }.to_json)

      TurnstileVerifier.call(token: "bon-jeton", ip: "203.0.113.1")

      assert_requested :post, ENDPOINT, body: hash_including(
        "secret" => PLACEHOLDER_SECRET, "response" => "bon-jeton", "remoteip" => "203.0.113.1"
      )
    end
  end

  test "a token Cloudflare rejects fails, and carries the reason" do
    with_secret do
      stub_request(:post, ENDPOINT).to_return(
        body: { success: false, "error-codes": [ "invalid-input-response" ] }.to_json
      )

      result = TurnstileVerifier.call(token: "mauvais-jeton")

      assert_not_predicate result, :success?
      assert_includes result.error_codes, "invalid-input-response"
    end
  end

  test "an empty token fails without calling Cloudflare" do
    with_secret do
      result = TurnstileVerifier.call(token: "")

      assert_not_predicate result, :success?
      assert_not_requested :post, ENDPOINT
    end
  end

  test "Cloudflare being unreachable fails rather than letting everyone through" do
    with_secret do
      stub_request(:post, ENDPOINT).to_timeout

      result = TurnstileVerifier.call(token: "bon-jeton")

      assert_not_predicate result, :success?
      assert_not_predicate result, :skipped?
      assert_includes result.error_codes, "verification-unavailable"
    end
  end

  test "an unreadable answer fails the same way" do
    with_secret do
      stub_request(:post, ENDPOINT).to_return(body: "<html>oops</html>")

      assert_not_predicate TurnstileVerifier.call(token: "bon-jeton"), :success?
    end
  end

  private
    def with_secret
      ENV["TURNSTILE_SECRET_KEY"] = PLACEHOLDER_SECRET
      ENV["TURNSTILE_SITE_KEY"] = PLACEHOLDER_SITE
      yield
    ensure
      ENV.delete("TURNSTILE_SECRET_KEY")
      ENV.delete("TURNSTILE_SITE_KEY")
    end
end
