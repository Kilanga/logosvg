require "application_system_test_case"

class DesignsTest < ApplicationSystemTestCase
  setup do
    ENV["GENERATOR_URL"] = "http://generator.test"
    ENV["GENERATOR_API_KEY"] = "not-a-key-generator-placeholder"
    ENV["GENERATOR_USER_KEY"] = "not-a-key-hmac-placeholder"
  end

  teardown do
    %w[ GENERATOR_URL GENERATOR_API_KEY GENERATOR_USER_KEY ].each { |k| ENV.delete(k) }
  end

  # The whole point of the step: a client describes an idea and watches a
  # printable file come back, bounded to what the shop can actually print.
  test "a client arriving by a shop's link generates a screen-printing design" do
    stub_generation(print_file: "design.svg", bytes: svg, result: {
      "palette" => [ { "hex" => "#1F5F7A" }, { "hex" => "#E4572E" } ],
      "inks" => 2, "stats" => { "paths" => 42 }, "warnings" => []
    })

    sign_in users(:client)
    visit workshop_link_path(slug: printers(:rennes).slug)

    # The shop's link narrows what is on offer to what it actually does.
    assert_text shown(printers(:rennes).name)
    assert_text displayed("designs.family_hint.vector")

    choose "design_technique_screen_printing", allow_label_click: true
    fill_in "design_prompt", with: "un renard qui fait du skate"

    # The size is asked here too, though screen printing is vectorial: it is
    # what decides which workshops can take the job.
    assert_text displayed("client.designs.new.size_legend")
    click_on I18n.t("client.designs.new.size_presets.chest")

    perform_enqueued_jobs do
      click_on I18n.t("client.designs.new.submit")
      assert_selector "h1", text: shown("un renard qui fait du skate")
    end

    design = Design.order(:created_at).last

    assert_equal 25, design.print_width_cm
    assert_equal printers(:rennes), design.printer
    assert_predicate design.reload, :ready?

    visit design_path(design)

    # Vector output is counted in screens, and each ink is one.
    assert_text displayed("client.designs.design.screens", count: 2)
    assert_text "#1F5F7A"
    assert_selector "img[src='#{design_image_path(design)}']"

    # Compatibility is the answer the client came for.
    assert_text displayed("client.designs.show.who_can_print")
    assert_text shown(printers(:rennes).name)
  end

  # The other family: no screens to count, a file measured in pixels instead.
  test "a client generates a dtf design and reads it in pixels, not in screens" do
    stub_generation(print_file: "print.png", bytes: png, result: {
      "palette" => [], "warnings" => [],
      "stats" => { "width_px" => 2835, "dpi" => 300, "net_width_cm" => 13,
                   "print_width_cm" => 24, "print_height_cm" => 24 }
    })

    sign_in users(:client)
    visit workshop_link_path(slug: printers(:lyon).slug)

    assert_text displayed("designs.family_hint.raster")

    choose "design_technique_dtf", allow_label_click: true
    fill_in "design_prompt", with: "une montagne au lever du soleil"

    perform_enqueued_jobs do
      click_on I18n.t("client.designs.new.submit")
      assert_selector "h1", text: shown("une montagne au lever du soleil")
    end

    design = Design.order(:created_at).last

    assert_predicate design.reload, :ready?
    assert_equal "png", design.print_format

    visit design_path(design)

    assert_text displayed("client.designs.design.print_file")
    assert_text displayed("designs.facts.resolution")
    assert_text "300 dpi"
    assert_no_text displayed("client.designs.design.screens", count: 1)
  end

  # A failure is a designed state, not a blank panel — and it costs the client
  # nothing.
  test "a refused prompt is explained on the page, and the attempt comes back" do
    stub_request(:post, "http://generator.test/generate").to_return(
      status: 422, body: { detail: "Cette demande contient une marque non autorisée." }.to_json
    )

    sign_in users(:client)
    visit new_design_path

    choose "design_technique_screen_printing", allow_label_click: true
    fill_in "design_prompt", with: "le logo d'une grande marque de sport"

    # The wait has to be inside the block: `click_on` hands back as soon as the
    # click is dispatched, and without an assertion that waits, jobs stop being
    # performed inline before the server thread has even read the request.
    perform_enqueued_jobs do
      click_on I18n.t("client.designs.new.submit")
      assert_selector "h1", text: shown("le logo d'une grande marque de sport")
    end

    assert_text displayed("client.designs.design.failed")
    assert_text "Cette demande contient une marque non autorisée."
    assert_link I18n.t("client.designs.design.try_again")

    assert_equal 0, GenerationQuota.for(users(:client)).used, "a failure consumes no attempt"
  end

  # A client pictures a chest logo or a back print, not a number of
  # centimetres. The presets speak that language and fill the field.
  test "the size presets fill the width, and the template follows" do
    sign_in users(:client)
    visit new_design_path

    click_on I18n.t("client.designs.new.size_presets.small_logo")

    # The caption is uppercased by `label-rule`, and a browser reports text as
    # it is rendered.
    assert_field "design_print_width_cm", with: "10"
    assert_selector "figcaption", text: shown("10 cm")

    click_on I18n.t("client.designs.new.size_presets.large_back")

    assert_field "design_print_width_cm", with: "36"
    assert_selector "figcaption", text: shown("36 cm")

    # A width typed by hand is as good as a preset, and the drawing follows it.
    fill_in "design_print_width_cm", with: "18"

    assert_selector "figcaption", text: shown("18 cm")
  end

  # Why the size matters is not the same question in both families, and the
  # screen must not give the wrong reason.
  test "the size explanation follows the technique" do
    sign_in users(:client)
    visit workshop_link_path(slug: printers(:nantes).slug)

    choose "design_technique_sublimation", allow_label_click: true

    assert_text displayed("client.designs.new.size_hint.raster")

    choose "design_technique_embroidery", allow_label_click: true

    assert_text displayed("client.designs.new.size_hint.vector")
  end

  test "a design still being generated shows a drawn waiting state, not a blank panel" do
    sign_in users(:client)
    designs(:pending_design).start!
    designs(:pending_design).save!

    visit design_path(designs(:pending_design))

    assert_text displayed("client.designs.design.working")
    assert_selector "[role='status']"
  end

  private
    def sign_in(user)
      visit new_session_path
      fill_in I18n.t("activerecord.attributes.user.email_address"), with: user.email_address
      fill_in I18n.t("activerecord.attributes.user.password"), with: "motdepasse-test"
      click_on I18n.t("sessions.new.submit")

      # A helper that hands back before the redirect has landed makes the test
      # fail much later, on a symptom with nothing to do with the cause.
      assert_no_current_path new_session_path
    end

    # The microservice, from the call that opens a job to the file that comes
    # back — the whole exchange PollDesignJob walks through.
    def stub_generation(print_file:, bytes:, result:)
      stub_request(:post, "http://generator.test/generate").to_return(
        body: { job_id: "job-sys", status: "queued", refinements_left: 3 }.to_json
      )
      stub_request(:get, %r{/jobs/job-sys\?}).to_return(
        body: {
          status: "done", refinements_left: 3,
          result: result.merge("print_file" => print_file, "prompt_used" => "…", "seed" => 1)
        }.to_json
      )
      stub_request(:get, %r{/jobs/job-sys/#{Regexp.escape(print_file)}}).to_return(body: bytes)
      stub_request(:get, %r{/jobs/job-sys/source\.png}).to_return(status: 404, body: "{}")
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 10 10">) +
        %(<path d="M0 0h5v10H0z" fill="#1F5F7A"/><path d="M5 0h5v10H5z" fill="#E4572E"/></svg>)
    end

    def png
      Base64.decode64(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
      )
    end
end
