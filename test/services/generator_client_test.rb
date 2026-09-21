require "test_helper"

class GeneratorClientTest < ActiveSupport::TestCase
  GENERATE = "http://generator.test/generate".freeze

  setup do
    ENV["GENERATOR_URL"] = "http://generator.test"
    ENV["GENERATOR_API_KEY"] = "not-a-key-generator-placeholder"
    ENV["GENERATOR_USER_KEY"] = "not-a-key-hmac-placeholder"
  end

  teardown do
    %w[ GENERATOR_URL GENERATOR_API_KEY GENERATOR_USER_KEY ].each { |k| ENV.delete(k) }
  end

  test "a generation carries the technique, and the key travels in the header" do
    stub_request(:post, GENERATE).to_return(body: { job_id: "abc", status: "queued" }.to_json)

    GeneratorClient.new.generate(designs(:pending_design))

    assert_requested :post, GENERATE, headers: { "X-API-Key" => "not-a-key-generator-placeholder" } do |request|
      body = JSON.parse(request.body)
      body["technique"] == "screen_printing" && body["colors"] == 2 && body["prompt"].present?
    end
  end

  # The service never learns who the client is.
  test "the client is identified by an HMAC, never by their account id" do
    stub_request(:post, GENERATE).to_return(body: "{}")

    GeneratorClient.new.generate(designs(:pending_design))

    assert_requested :post, GENERATE do |request|
      sent = JSON.parse(request.body)["user_id"]
      sent.match?(/\A[a-f0-9]{32}\z/) &&
        sent != users(:client).id.to_s &&
        !request.body.include?(users(:client).email_address)
    end
  end

  test "the same client always gets the same pseudonym, and two clients never share one" do
    stub_request(:post, GENERATE).to_return(body: "{}")

    sent = []
    2.times { GeneratorClient.new.generate(designs(:pending_design)) }
    GeneratorClient.new.generate(designs(:other_client_design))

    WebMock::RequestRegistry.instance.requested_signatures.hash.each_key do |signature|
      sent << JSON.parse(signature.body)["user_id"]
    end

    assert_equal 2, sent.uniq.size
  end

  test "a technique with no ink ceiling sends no colours at all" do
    stub_request(:post, GENERATE).to_return(body: "{}")

    GeneratorClient.new.generate(designs(:fox_dtf))

    assert_requested(:post, GENERATE) { |request| !JSON.parse(request.body).key?("colors") }
  end

  test "a blocked term comes back with the sentence to show the client" do
    stub_request(:post, GENERATE).to_return(
      status: 422, body: { detail: "Cette demande contient une marque non autorisée." }.to_json
    )

    error = assert_raises(GeneratorClient::Rejected) { GeneratorClient.new.generate(designs(:pending_design)) }

    assert_equal "Cette demande contient une marque non autorisée.", error.detail
  end

  # The two 429s mean opposite things, and only the body tells them apart.
  test "the hourly limit is a wait, and carries how long" do
    stub_request(:post, GENERATE).to_return(
      status: 429, headers: { "Retry-After" => "300" }, body: { detail: "Limite atteinte." }.to_json
    )

    error = assert_raises(GeneratorClient::RateLimited) { GeneratorClient.new.generate(designs(:pending_design)) }

    assert_equal 300, error.retry_after
  end

  test "an exhausted refinement budget is definitive, and a different failure entirely" do
    stub_request(:post, %r{/jobs/abc/refine}).to_return(
      status: 429, body: { detail: "Plus de reprises.", reason: "refine_budget", refinements_left: 0 }.to_json
    )

    assert_raises(GeneratorClient::BudgetExhausted) do
      GeneratorClient.new.refine("abc", instruction: "un casque rouge", user_id: users(:client).id)
    end
  end

  test "a refinement asked before the previous version is ready" do
    stub_request(:post, %r{/jobs/abc/refine}).to_return(status: 409, body: { detail: "Pas prêt." }.to_json)

    assert_raises(GeneratorClient::NotReady) do
      GeneratorClient.new.refine("abc", instruction: "un casque rouge", user_id: users(:client).id)
    end
  end

  test "a refused key is a configuration fault" do
    stub_request(:post, GENERATE).to_return(status: 401, body: "{}")

    assert_raises(GeneratorClient::Unauthorized) { GeneratorClient.new.generate(designs(:pending_design)) }
  end

  test "a full queue and an unreachable service are the same problem to the caller" do
    stub_request(:post, GENERATE).to_return(status: 503, body: { detail: "File pleine." }.to_json)
    assert_raises(GeneratorClient::Unavailable) { GeneratorClient.new.generate(designs(:pending_design)) }

    stub_request(:post, GENERATE).to_timeout
    assert_raises(GeneratorClient::Unavailable) { GeneratorClient.new.generate(designs(:pending_design)) }
  end

  test "an error body that is not JSON still raises the right kind of failure" do
    stub_request(:post, GENERATE).to_return(status: 503, body: "<html>bad gateway</html>")

    assert_raises(GeneratorClient::Unavailable) { GeneratorClient.new.generate(designs(:pending_design)) }
  end

  test "a job belonging to someone else is not found" do
    stub_request(:get, %r{/jobs/abc}).to_return(status: 404, body: "{}")

    assert_raises(GeneratorClient::NotFound) { GeneratorClient.new.job("abc", user_id: users(:client).id) }
  end

  test "a file is fetched by the name the service gave, never by a guessed extension" do
    stub_request(:get, %r{/jobs/abc/print\.png}).to_return(body: "des octets")

    assert_equal "des octets", GeneratorClient.new.download("abc", "print.png", user_id: users(:client).id)
  end

  test "without a pseudonymisation key nothing leaves the application" do
    ENV.delete("GENERATOR_USER_KEY")

    assert_raises(GeneratorClient::Unavailable) { GeneratorClient.new.generate(designs(:pending_design)) }
    assert_not_requested :post, GENERATE
  end
end
