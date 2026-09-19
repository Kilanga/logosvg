require "test_helper"

class PollDesignJobTest < ActiveJob::TestCase
  JOB = "http://generator.test/jobs/job-42".freeze

  setup do
    ENV["GENERATOR_URL"] = "http://generator.test"
    ENV["GENERATOR_API_KEY"] = "not-a-key-generator-placeholder"
    ENV["GENERATOR_USER_KEY"] = "not-a-key-hmac-placeholder"

    @design = designs(:pending_design)
    @design.update!(generator_job_id: "job-42")
    @design.start!
    @design.save!

    GenerationQuota.for(@design.user).consume!
  end

  teardown do
    %w[ GENERATOR_URL GENERATOR_API_KEY GENERATOR_USER_KEY ].each { |k| ENV.delete(k) }
  end

  test "a generation still running is asked again later" do
    stub_answer(status: "running", position: 2)

    assert_enqueued_with(job: PollDesignJob) { PollDesignJob.perform_now(@design) }

    assert_predicate @design.reload, :generating?
  end

  test "a finished generation is brought home and the design turns ready" do
    stub_answer(status: "done", refinements_left: 2, result: {
      print_file: "design.svg", palette: [ { hex: "#1F5F7A" } ], inks: 1,
      stats: { paths: 12 }, warnings: [], prompt_used: "screen print, a mountain", seed: 7
    })
    stub_request(:get, %r{/jobs/job-42/design\.svg}).to_return(body: svg)
    stub_request(:get, %r{/jobs/job-42/source\.png}).to_return(status: 404, body: "{}")

    PollDesignJob.perform_now(@design)
    @design.reload

    assert_predicate @design, :ready?
    assert_predicate @design.print_file, :attached?
    assert_equal "svg", @design.print_format
    assert_equal 2, @design.refinements_left
    assert_equal 1, @design.inks_count
  end

  test "a generation the service gave up on carries its reason, and costs nothing" do
    stub_answer(status: "error", error: "Le modèle n'a rien produit d'exploitable.")

    PollDesignJob.perform_now(@design)

    assert_predicate @design.reload, :failed?
    assert_equal "Le modèle n'a rien produit d'exploitable.", @design.error_message
    assert_equal 0, GenerationQuota.for(@design.user).used
  end

  # Five minutes is the whole budget: a job that never finishes must not poll
  # for ever.
  test "polling stops at the timeout rather than running on" do
    stub_answer(status: "running")

    assert_no_enqueued_jobs(only: PollDesignJob) do
      PollDesignJob.perform_now(@design, started_at: 1.hour.ago)
    end

    assert_predicate @design.reload, :failed?
    assert_equal I18n.t("designs.errors.timed_out"), @design.error_message
  end

  # The generation machine keeps files an hour; after that there is nothing to
  # wait for.
  test "a job that has expired off the machine stops the wait" do
    stub_request(:get, %r{/jobs/job-42}).to_return(status: 404, body: "{}")

    PollDesignJob.perform_now(@design)

    assert_predicate @design.reload, :failed?
    assert_equal I18n.t("designs.errors.expired"), @design.error_message
  end

  # A dropped tunnel is worth waiting through; a refused file is not.
  test "an unreachable service is waited through, not given up on" do
    stub_request(:get, %r{/jobs/job-42}).to_timeout

    assert_enqueued_with(job: PollDesignJob) { PollDesignJob.perform_now(@design) }

    assert_predicate @design.reload, :generating?
  end

  test "an svg the inspector refuses is never attached, and costs no attempt" do
    stub_answer(status: "done", result: { print_file: "design.svg", stats: {} })
    stub_request(:get, %r{/jobs/job-42/design\.svg}).to_return(
      body: %(<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>)
    )

    PollDesignJob.perform_now(@design)
    @design.reload

    assert_predicate @design, :failed?
    assert_not_predicate @design.print_file, :attached?
    assert_equal I18n.t("designs.errors.unusable_file"), @design.error_message
    assert_equal 0, GenerationQuota.for(@design.user).used
  end

  test "a design no longer generating is left alone" do
    @design.succeed!
    @design.save!

    PollDesignJob.perform_now(@design)

    assert_not_requested :get, %r{/jobs/job-42}
  end

  private
    def stub_answer(**answer)
      stub_request(:get, %r{/jobs/job-42\?}).to_return(body: answer.to_json)
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">) +
        %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>)
    end
end
