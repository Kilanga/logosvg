require "test_helper"

class DesignsTest < ActionDispatch::IntegrationTest
  GENERATE = "http://generator.test/generate".freeze

  setup do
    ENV["GENERATOR_URL"] = "http://generator.test"
    ENV["GENERATOR_API_KEY"] = "not-a-key-generator-placeholder"
    ENV["GENERATOR_USER_KEY"] = "not-a-key-hmac-placeholder"
  end

  teardown do
    %w[ GENERATOR_URL GENERATOR_API_KEY GENERATOR_USER_KEY ].each { |k| ENV.delete(k) }
  end

  # --- Creating ------------------------------------------------------------

  test "a client describes an idea and the generation is handed to a job" do
    sign_in_as users(:client)

    assert_enqueued_with(job: GenerateDesignJob) do
      post designs_path, params: { design: valid_design }
    end

    design = Design.order(:created_at).last

    assert_redirected_to design_path(design)
    assert_predicate design, :pending?
    assert_equal users(:client), design.user
  end

  # Appels réseau uniquement depuis des jobs de fond.
  test "creating a design reaches no network in the request itself" do
    sign_in_as users(:client)

    post designs_path, params: { design: valid_design }

    assert_not_requested :post, GENERATE
  end

  test "an unusable prompt comes back with the form rather than a queued job" do
    sign_in_as users(:client)

    assert_no_enqueued_jobs(only: GenerateDesignJob) do
      post designs_path, params: { design: valid_design.merge(prompt: "ab") }
    end

    assert_response :unprocessable_entity
  end

  test "a refused design hands the attempt back" do
    sign_in_as users(:client)

    post designs_path, params: { design: valid_design.merge(prompt: "ab") }

    assert_equal 0, GenerationQuota.for(users(:client)).used
  end

  test "the daily allowance stops the sixth attempt of the day" do
    sign_in_as users(:client)
    GenerationQuota.per_day.times { GenerationQuota.for(users(:client)).consume! }

    assert_no_enqueued_jobs(only: GenerateDesignJob) do
      post designs_path, params: { design: valid_design }
    end

    assert_response :unprocessable_entity
  end

  # The shop's press is the real ceiling, whatever the form was made to send.
  test "a request beyond the shop's press is brought back within it" do
    sign_in_as users(:client)
    get workshop_link_path(slug: printers(:rennes).slug)

    post designs_path, params: { design: valid_design.merge(colors_requested: 6, print_width_cm: 50) }

    design = Design.order(:created_at).last

    assert_equal 4, design.colors_requested, "Rennes prints four screens"
    assert_equal 30, design.print_width_cm
    assert_equal printers(:rennes), design.printer
  end

  test "a shop's link is remembered for the whole session" do
    sign_in_as users(:client)

    get workshop_link_path(slug: printers(:lyon).slug)

    assert_redirected_to new_design_path

    get new_design_path

    assert_response :success
    assert_select "body", text: /Presse Rhône/i
  end

  test "a link to a shop that is no longer listed sends the client to the directory" do
    sign_in_as users(:client)

    get workshop_link_path(slug: printers(:brouillon).slug)

    assert_redirected_to printers_path
  end

  test "only a client generates" do
    [ :printer, :designer, :admin ].each do |role|
      sign_in_as users(role)

      get new_design_path

      assert_response :redirect, "#{role} must not reach the creation screen"

      sign_out
    end
  end

  test "a visitor is sent to sign in rather than to the form" do
    get new_design_path

    assert_redirected_to new_session_path
  end

  # --- Reading -------------------------------------------------------------

  test "a client reads their own design" do
    sign_in_as users(:client)

    get design_path(designs(:fox_screen))

    assert_response :success
  end

  # The token is unguessable precisely so a leaked link is the only way anyone
  # else could try — and it still fails.
  test "a design is not readable by anyone but its owner" do
    sign_in_as users(:client)

    get design_path(designs(:other_client_design))

    assert_response :not_found
  end

  test "a soft-deleted design is gone for its owner too" do
    designs(:fox_screen).soft_delete!
    sign_in_as users(:client)

    get design_path(designs(:fox_screen))

    assert_response :not_found
  end

  # --- Files ---------------------------------------------------------------

  # The decision the whole preview service exists for: the client downloads the
  # watermarked PNG, never the print file.
  test "the download is a watermarked png, whatever the print file is" do
    design = attached_design
    sign_in_as users(:client)

    get design_image_path(design)

    assert_response :success
    assert_equal "image/png", response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_equal "\x89PNG".b, response.body.byteslice(0, 4)
  end

  test "a design with no file yet has nothing to download" do
    sign_in_as users(:client)

    get design_image_path(designs(:pending_design))

    assert_response :not_found
  end

  # The client is offered the watermarked preview and nothing else: no link on
  # the page reaches the stored print file.
  test "the design page never hands out the print file" do
    design = attached_design
    sign_in_as users(:client)

    get design_path(design)

    assert_select "a[href=?]", design_image_path(design)
    assert_select "a[href*=?]", "/rails/active_storage", count: 0
    assert_select "img[src=?]", design_image_path(design)
    assert_no_match(/#{Regexp.escape(design.print_file.filename.to_s)}/, response.body)
  end

  # --- Taking it further ---------------------------------------------------

  test "variants make children of the same lineage" do
    sign_in_as users(:client)
    designs(:fox_screen).update!(generator_job_id: "job-42")
    stub_request(:post, %r{/jobs/job-42/variants}).to_return(
      body: { job_ids: %w[ v1 v2 v3 ], job_id: "v1", refinements_left: 2 }.to_json
    )

    assert_difference "Design.count", 3 do
      post design_variants_path(designs(:fox_screen))
    end

    assert_equal designs(:fox_screen), Design.order(:created_at).last.root
  end

  # The budget is the service's to count, and running out opens the designer
  # path rather than simply failing.
  test "an exhausted refinement budget is told to the client, and costs no attempt" do
    sign_in_as users(:client)
    designs(:fox_screen).update!(generator_job_id: "job-42")
    stub_request(:post, %r{/jobs/job-42/refine}).to_return(
      status: 429, body: { detail: "Plus de reprises.", reason: "refine_budget" }.to_json
    )

    assert_no_difference "Design.count" do
      post design_refine_path(designs(:fox_screen)), params: { instruction: "un casque rouge" }
    end

    assert_redirected_to design_path(designs(:fox_screen))
    assert_equal 0, GenerationQuota.for(users(:client)).used
  end

  test "a design still generating cannot be taken further" do
    sign_in_as users(:client)

    post design_variants_path(designs(:pending_design))

    assert_response :redirect
    assert_not_requested :post, %r{/variants}
  end

  test "nobody takes another client's design further" do
    sign_in_as users(:client)

    post design_variants_path(designs(:other_client_design))

    assert_response :not_found
  end

  private
    def valid_design
      { prompt: "un renard qui fait du skate", style: "mascotte",
        technique: "screen_printing", colors_requested: 3, print_width_cm: 25 }
    end

    def attached_design
      designs(:fox_screen).tap do |design|
        design.print_file.attach(
          io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml"
        )
      end
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 10 10">) +
        %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>)
    end
end
