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

    design = first_of_last_click

    assert_redirected_to design_path(design)
    assert_predicate design, :pending?
    assert_equal users(:client), design.user
  end

  # Decided in October 2026: every click draws three proposals, each with its
  # own take, and counts as one generation.
  test "a creation makes three proposals of one click, counted once" do
    sign_in_as users(:client)

    assert_difference "Design.count", 3 do
      assert_enqueued_jobs 1, only: GenerateDesignJob do
        post designs_path, params: { design: valid_design }
      end
    end

    proposals = first_of_last_click.proposals.to_a
    assert_equal 3, proposals.size
    assert proposals.all?(&:awaiting_choice?)
    assert proposals.all?(&:pending?)
    assert_equal [ valid_design[:prompt] ], proposals.map(&:prompt).uniq
    assert_equal 1, GenerationQuota.for(users(:client)).used
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

  # Asked of the client now, and checked on the server: the drawing and the
  # presets are a convenience, not the rule.
  test "a design submitted without a size comes back with the form" do
    sign_in_as users(:client)

    assert_no_enqueued_jobs(only: GenerateDesignJob) do
      post designs_path, params: { design: valid_design.merge(print_width_cm: "") }
    end

    assert_response :unprocessable_entity
  end

  test "the size is asked for a vector technique as much as for a raster one" do
    sign_in_as users(:client)

    get new_design_path

    assert_select "input[name=?]", "design[print_width_cm]"
    assert_select "legend", text: /#{Regexp.escape(I18n.t('client.designs.new.size_legend'))}/i
  end

  test "the daily allowance stops the sixth attempt of the day" do
    sign_in_as users(:client)
    GenerationQuota.per_day.times { GenerationQuota.for(users(:client)).consume! }

    assert_no_enqueued_jobs(only: GenerateDesignJob) do
      post designs_path, params: { design: valid_design }
    end

    assert_response :unprocessable_entity
  end

  # --- Starting from the client's own image (decided 06/10/2026) ----------

  test "a client may start from an image of their own, re-encoded before it is kept" do
    sign_in_as users(:client)

    post designs_path, params: { design: valid_design.merge(
      reference_image: upload(jpeg_with_exif, "image/jpeg", "photo.jpg"), reference_rights_confirmed: "1"
    ) }

    design = first_of_last_click
    assert_redirected_to design_path(design)
    assert_predicate design.reference_image, :attached?
    assert design.proposals.all? { |proposal| proposal.reference_image.attached? },
           "every proposal is a root, and keeps the image its children start from"
    assert_equal "image/png", design.reference_image.content_type
    stored = Vips::Image.new_from_buffer(design.reference_image.download, "")
    assert_not_includes stored.get_fields, "exif-data", "the phone's metadata must not survive"

    get design_reference_image_path(design)
    assert_response :success
  end

  test "the image is sent to the generation service with the request" do
    design = designs(:pending_design)
    design.reference_image.attach(io: StringIO.new(png), filename: "image-de-depart.png", content_type: "image/png")
    stub_request(:post, GENERATE).to_return(status: 202, body: { job_id: "j1", status: "queued" }.to_json)

    GeneratorClient.new.generate(design)

    assert_requested :post, GENERATE do |request|
      Base64.strict_decode64(JSON.parse(request.body)["init_image"]) == design.reference_image.download
    end
  end

  test "without the rights checkbox, an image is refused and nothing is generated" do
    sign_in_as users(:client)

    assert_no_difference "Design.count" do
      post designs_path, params: { design: valid_design.merge(reference_image: upload(png, "image/png", "logo.png")) }
    end

    assert_response :unprocessable_entity
    assert_equal 0, GenerationQuota.for(users(:client)).used
  end

  test "an image of another kind is refused with a sentence the client understands" do
    sign_in_as users(:client)

    post designs_path, params: { design: valid_design.merge(
      reference_image: upload(svg, "image/png", "faux.png"), reference_rights_confirmed: "1"
    ) }

    assert_response :unprocessable_entity
    assert_includes response.body, ERB::Util.html_escape(I18n.t("client.designs.reference_image.errors.wrong_type"))
  end

  test "starting from an image stays optional" do
    sign_in_as users(:client)

    post designs_path, params: { design: valid_design }

    assert_not_predicate Design.order(:created_at).last.reference_image, :attached?
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

  # The Référencement plan's monthly ceiling, counted on the workshop.
  test "a workshop that used its month's generations stops new ones, and the client is told why" do
    sign_in_as users(:client)
    get workshop_link_path(slug: printers(:rennes).slug)
    quota = PrinterGenerationQuota.for(printers(:rennes))
    rows = Array.new(quota.limit - quota.used) do
      { user_id: users(:deleted_client).id, printer_id: printers(:rennes).id, prompt: "un renard",
        technique: "screen_printing", print_width_cm: 25, status: "ready",
        token: SecureRandom.base58(24), created_at: Time.current, updated_at: Time.current }
    end
    Design.insert_all!(rows)

    assert_no_difference "Design.count" do
      post designs_path, params: { design: valid_design }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, ERB::Util.html_escape(
      I18n.t("client.designs.workshop_quota_reached", printer: printers(:rennes).name)
    ).split(",").first
    assert_equal 0, GenerationQuota.for(users(:client)).used, "the client's own allowance is untouched"
  end

  test "the last generation of the month tells the workshop" do
    sign_in_as users(:client)
    get workshop_link_path(slug: printers(:rennes).slug)
    quota = PrinterGenerationQuota.for(printers(:rennes))
    rows = Array.new(quota.limit - quota.used - 1) do
      { user_id: users(:deleted_client).id, printer_id: printers(:rennes).id, prompt: "un renard",
        technique: "screen_printing", print_width_cm: 25, status: "ready",
        token: SecureRandom.base58(24), created_at: Time.current, updated_at: Time.current }
    end
    Design.insert_all!(rows) if rows.any?

    assert_enqueued_email_with SubscriptionMailer, :generation_quota_reached, args: [ printers(:rennes) ] do
      post designs_path, params: { design: valid_design }
    end
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

  # The comparison selector's other half — also watermarked, also never the
  # deciding rendering. See docs/SPEC.md, "Aperçu".
  test "the original image is also a watermarked png, when one was kept" do
    design = attached_design
    design.source_png.attach(io: StringIO.new(png), filename: "source.png", content_type: "image/png")
    sign_in_as users(:client)

    get design_original_image_path(design)

    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal "\x89PNG".b, response.body.byteslice(0, 4)
  end

  test "a design with no original image kept has nothing to compare against" do
    design = attached_design
    sign_in_as users(:client)

    get design_original_image_path(design)

    assert_response :not_found
  end

  test "another client cannot reach the original image either" do
    design = designs(:other_client_design)
    design.source_png.attach(io: StringIO.new(png), filename: "source.png", content_type: "image/png")
    sign_in_as users(:client)

    get design_original_image_path(design)

    assert_response :not_found
  end

  test "the garment rendering is a transparent, watermarked png for the owner only" do
    design = attached_design
    sign_in_as users(:client)

    get design_garment_image_path(design)

    assert_response :success
    assert_equal "image/png", response.media_type
    assert Vips::Image.new_from_buffer(response.body, "").has_alpha?
    assert AiProvenance.marked?(response.body)
  end

  test "the page says the picture was drawn by an AI" do
    design = attached_design
    sign_in_as users(:client)

    get design_path(design)

    assert_includes response.body, I18n.t("designs.ai_label")
  end

  # The client is offered the watermarked preview and nothing else: no link on
  # the page reaches the stored print file.
  test "the design page never hands out the print file" do
    design = attached_design
    sign_in_as users(:client)

    get design_path(design)

    assert_select "a[href=?]", design_image_path(design)
    assert_select "a[href*=?]", "/rails/active_storage", count: 0
    # The silhouette shows the transparent rendering — still a watermarked
    # preview, never the stored file.
    assert_select "img[src=?]", design_garment_image_path(design)
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

  test "the variants of one click share a batch token, and count as one reprise" do
    sign_in_as users(:client)
    designs(:fox_screen).update!(generator_job_id: "job-42")
    stub_request(:post, %r{/jobs/job-42/variants}).to_return(
      body: { job_ids: %w[ v1 v2 v3 ], job_id: "v1", refinements_left: 2 }.to_json
    )

    post design_variants_path(designs(:fox_screen))

    children = Design.where(parent: designs(:fox_screen))
    assert_equal 1, children.distinct.count(:batch_token)
    assert_equal 1, designs(:fox_screen).refinements_used
  end

  # The service forgets its count whenever its machine is switched off: the
  # application's own count is the one that closes the lineage.
  test "a lineage that spent its reprises is closed without asking the service" do
    sign_in_as users(:client)
    designs(:fox_screen).update!(generator_job_id: "job-42")
    3.times { |i| spend_a_reprise(designs(:fox_screen), "r#{i}") }

    assert_no_difference "Design.count" do
      post design_refine_path(designs(:fox_screen)), params: { instruction: "un casque rouge" }
    end

    assert_redirected_to design_path(designs(:fox_screen))
    assert_not_requested :post, %r{/refine}
    assert_equal 0, GenerationQuota.for(users(:client)).used
  end

  # The machine is switched off every evening: tomorrow it knows nothing of
  # today's designs. The application hands the design back, then asks again.
  test "a design the machine forgot is restored, then taken further" do
    sign_in_as users(:client)
    design = designs(:fox_screen)
    design.update!(generator_job_id: "job-42")
    design.source_png.attach(io: StringIO.new(png), filename: "source.png", content_type: "image/png")
    spend_a_reprise(design, "earlier")

    stub_request(:post, %r{/jobs/job-42/refine}).to_return(
      status: 404, body: { detail: "Design introuvable ou expiré." }.to_json
    )
    restore = stub_request(:post, %r{/jobs/restore})
      .with { |request| JSON.parse(request.body).values_at("used_refinements", "subject") == [ 1, design.subject ] }
      .to_return(status: 201, body: { job_id: "restored-1", status: "done", refinements_left: 2 }.to_json)
    stub_request(:post, %r{/jobs/restored-1/refine}).to_return(
      status: 202, body: { job_id: "child-1", status: "queued", refinements_left: 1 }.to_json
    )

    assert_difference "Design.count", 1 do
      post design_refine_path(design), params: { instruction: "un casque rouge" }
    end

    assert_requested restore
    assert_equal "restored-1", design.reload.generator_job_id
    assert_equal "child-1", Design.order(:created_at).last.generator_job_id
  end

  test "a forgotten design with no original image is said to be too old" do
    sign_in_as users(:client)
    designs(:fox_screen).update!(generator_job_id: "job-42")
    stub_request(:post, %r{/jobs/job-42/variants}).to_return(status: 404, body: "{}")

    assert_no_difference "Design.count" do
      post design_variants_path(designs(:fox_screen))
    end

    assert_equal I18n.t("client.designs.take_it_further.too_old"), flash[:alert]
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

  # --- Choosing among the proposals --------------------------------------

  # Decided on 07/10/2026: pick and retouch on the same page.
  test "the proposals of a click are shown together, with the retouch on the same page" do
    sign_in_as users(:client)
    proposals = ready_proposals

    get design_path(proposals.first)

    assert_response :success
    proposals.each { |proposal| assert_select "#design_#{proposal.token}" }
    assert_select "form[action=?][data-proposals-refine-url-param=?]",
                  design_choice_path(proposals.second), design_refine_path(proposals.second)
    assert_select "[data-controller=proposals] textarea[name=instruction]", count: 1
    assert_select "form[data-kind=choice] input[name=suite][value=atelier]"
  end

  test "keeping a proposal sets the others aside" do
    sign_in_as users(:client)
    proposals = ready_proposals

    post design_choice_path(proposals.second)

    assert_redirected_to design_path(proposals.second)
    assert_not proposals.second.reload.awaiting_choice?
    assert proposals.values_at(0, 2).map(&:reload).none?(&:active?)
    follow_redirect!
    assert_select "form[action=?]", design_refine_path(proposals.second)
  end

  test "retouching a proposal keeps it and sets the others aside" do
    sign_in_as users(:client)
    proposals = ready_proposals
    proposals.second.update!(generator_job_id: "job-2")
    stub_request(:post, %r{/jobs/job-2/refine})
      .to_return(status: 202, body: { job_ids: %w[ r1 r2 r3 ], job_id: "r1", refinements_left: 2 }.to_json)

    post design_refine_path(proposals.second), params: { instruction: "un casque rouge" }

    assert_not proposals.second.reload.awaiting_choice?
    assert proposals.values_at(0, 2).map(&:reload).none?(&:active?)
    assert_equal 3, Design.where(parent: proposals.second).count
  end

  test "a failed retouche leaves every proposal on offer" do
    sign_in_as users(:client)
    proposals = ready_proposals
    stub_request(:post, %r{/refine}).to_return(status: 503, body: "{}")

    post design_refine_path(proposals.second), params: { instruction: "un casque rouge" }

    assert proposals.map(&:reload).all? { |proposal| proposal.active? && proposal.awaiting_choice? }
  end

  test "a proposal reaches a workshop only once kept, and keeping it can lead straight there" do
    sign_in_as users(:client)
    proposal = ready_proposals.first

    get new_design_print_request_path(proposal)
    assert_response :redirect
    assert_not_equal new_design_print_request_path(proposal), URI(response.location).path

    post design_choice_path(proposal), params: { suite: "atelier" }
    assert_redirected_to new_design_print_request_path(proposal)
  end

  test "a design already kept cannot be chosen again" do
    sign_in_as users(:client)

    post design_choice_path(designs(:fox_screen))

    assert_response :redirect
    assert_not_equal design_path(designs(:fox_screen)), response.location.sub("http://www.example.com", "")
  end

  test "a retouche draws three proposals to choose from, for one reprise" do
    sign_in_as users(:client)
    designs(:fox_screen).update!(generator_job_id: "job-42")
    stub_request(:post, %r{/jobs/job-42/refine})
      .with { |request| JSON.parse(request.body)["count"] == 3 }
      .to_return(status: 202, body: { job_ids: %w[ r1 r2 r3 ], job_id: "r1", refinements_left: 2 }.to_json)

    assert_difference "Design.count", 3 do
      post design_refine_path(designs(:fox_screen)), params: { instruction: "un casque rouge" }
    end

    assert Design.where(parent: designs(:fox_screen)).all?(&:awaiting_choice?)
    assert_equal 1, designs(:fox_screen).refinements_used
    assert_equal 1, GenerationQuota.for(users(:client)).used
  end

  private
    def ready_proposals
      design = designs(:fox_screen)
      design.update!(batch_token: "click-1", chosen_at: nil, refinements_left: 3)
      siblings = Array.new(2) do |index|
        design.dup.tap do |copy|
          copy.token = SecureRandom.base58(24)
          copy.generator_job_id = "sibling-#{index}"
          copy.save!
        end
      end
      [ design, *siblings ]
    end

    def first_of_last_click
      Design.where(batch_token: Design.order(:id).last.batch_token).order(:id).first
    end

    def spend_a_reprise(design, job_id)
      Design.create!(user: design.user, printer: design.printer, parent: design, root: design,
                     mode: "refine", instruction: "une retouche", prompt: design.prompt,
                     style: design.style, technique: design.technique,
                     colors_requested: design.colors_requested, print_width_cm: design.print_width_cm,
                     generator_job_id: job_id, status: "ready")
    end

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

    def upload(bytes, type, name)
      Rack::Test::UploadedFile.new(StringIO.new(bytes), type, original_filename: name)
    end

    # A JPEG carrying EXIF, as a phone photo would.
    def jpeg_with_exif
      image = Vips::Image.black(40, 30).add(120).cast(:uchar).bandjoin([ 60, 30 ]).copy(interpretation: :srgb)
      image = image.copy
      image.set_type(GObject::GSTR_TYPE, "exif-ifd0-Make", "Telephone (Make, ASCII, 10 components, 10 bytes)")
      image.write_to_buffer(".jpg")
    end

    def png
      Base64.decode64(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
      )
    end
end
