require "test_helper"

class GenerateDesignJobTest < ActiveJob::TestCase
  GENERATE = "http://generator.test/generate".freeze

  setup do
    ENV["GENERATOR_URL"] = "http://generator.test"
    ENV["GENERATOR_API_KEY"] = "not-a-key-generator-placeholder"
    ENV["GENERATOR_USER_KEY"] = "not-a-key-hmac-placeholder"

    @design = designs(:pending_design)
    # The attempt was taken when the form was submitted: every failure here has
    # to hand it back.
    GenerationQuota.for(@design.user).consume!
  end

  teardown do
    %w[ GENERATOR_URL GENERATOR_API_KEY GENERATOR_USER_KEY ].each { |k| ENV.delete(k) }
  end

  test "an accepted generation records the job id and waits for it" do
    stub_request(:post, GENERATE).to_return(
      body: { job_id: "job-42", status: "queued", position: 1, refinements_left: 3 }.to_json
    )

    assert_enqueued_with(job: PollDesignJob) { GenerateDesignJob.perform_now(@design) }

    @design.reload

    assert_predicate @design, :generating?
    assert_equal "job-42", @design.generator_job_id
    assert_equal 3, @design.refinements_left
  end

  test "a blocked term is shown to the client in the service's own words" do
    stub_request(:post, GENERATE).to_return(
      status: 422, body: { detail: "Cette demande contient une marque non autorisée." }.to_json
    )

    assert_no_enqueued_jobs(only: PollDesignJob) { GenerateDesignJob.perform_now(@design) }

    @design.reload

    assert_predicate @design, :failed?
    assert_equal "Cette demande contient une marque non autorisée.", @design.error_message
  end

  # The rule the whole quota table exists for.
  test "a generation that never reached the service costs no attempt" do
    stub_request(:post, GENERATE).to_return(status: 503, body: { detail: "File pleine." }.to_json)

    assert_equal 1, GenerationQuota.for(@design.user).used

    GenerateDesignJob.perform_now(@design)

    assert_equal 0, GenerationQuota.for(@design.user).used
    assert_predicate @design.reload, :failed?
  end

  test "an hourly limit tells the client when to come back" do
    stub_request(:post, GENERATE).to_return(
      status: 429, headers: { "Retry-After" => "300" }, body: { detail: "Limite atteinte." }.to_json
    )

    GenerateDesignJob.perform_now(@design)

    assert_match(/6 min/, @design.reload.error_message, "300 s, rounded up to the next minute")
  end

  # A key we got wrong is not something to explain to a client.
  test "a refused api key reads as an outage, never as the client's mistake" do
    stub_request(:post, GENERATE).to_return(status: 401, body: "{}")

    GenerateDesignJob.perform_now(@design)

    assert_equal I18n.t("designs.errors.unavailable"), @design.reload.error_message
  end

  test "a design already under way is not sent twice" do
    @design.start!
    @design.save!

    GenerateDesignJob.perform_now(@design)

    assert_not_requested :post, GENERATE
  end
end
