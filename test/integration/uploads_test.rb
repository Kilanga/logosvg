require "test_helper"

# Decided on 08/10/2026: a client who already has a finished picture sends it
# to the workshop in the right format, without the AI redrawing it.
class UploadsTest < ActionDispatch::IntegrationTest
  CONVERT = "http://generator.test/convert".freeze

  setup do
    ENV["GENERATOR_URL"] = "http://generator.test"
    ENV["GENERATOR_API_KEY"] = "not-a-key-generator-placeholder"
    ENV["GENERATOR_USER_KEY"] = "not-a-key-hmac-placeholder"
  end

  teardown do
    %w[ GENERATOR_URL GENERATOR_API_KEY GENERATOR_USER_KEY ].each { |k| ENV.delete(k) }
  end

  test "the creation form offers the way for a client who already has a picture" do
    sign_in_as users(:client)

    get new_design_path
    assert_select "a[href=?]", new_design_upload_path

    get new_design_upload_path
    assert_response :success
    assert_select "input[type=file][name=?]", "design[reference_image]"
  end

  test "a picture sent as is becomes one design, costs no generation, and is handed to a job" do
    sign_in_as users(:client)

    assert_difference "Design.count", 1 do
      assert_enqueued_with(job: GenerateDesignJob) do
        post design_uploads_path, params: { design: valid_upload }
      end
    end

    design = Design.order(:id).last
    assert_redirected_to design_path(design)
    assert_equal "upload", design.mode
    assert_nil design.batch_token, "one picture, no proposals to choose from"
    assert_equal "Logo du club", design.prompt
    assert_predicate design.reference_image, :attached?
    assert_equal 0, GenerationQuota.for(users(:client)).used
    assert_not design.ai_generated?, "not declared AI: no AI mark"
  end

  test "the definition of the picture is kept well beyond what the model works at" do
    sign_in_as users(:client)

    post design_uploads_path, params: { design: valid_upload.merge(reference_image: upload(png(2400, 1200), "image/png", "grand.png")) }

    stored = Vips::Image.new_from_buffer(Design.order(:id).last.reference_image.download, "")
    assert_equal [ 2400, 1200 ], [ stored.width, stored.height ]
  end

  test "a picture declared made with an AI is marked as such" do
    sign_in_as users(:client)

    post design_uploads_path, params: { design: valid_upload.merge(ai_declared: "1") }

    assert_predicate Design.order(:id).last, :ai_generated?
  end

  test "it still works once the daily generations are spent" do
    sign_in_as users(:client)
    GenerationQuota.per_day.times { GenerationQuota.for(users(:client)).consume! }

    assert_difference "Design.count", 1 do
      post design_uploads_path, params: { design: valid_upload }
    end
  end

  test "without a picture, or without the rights, nothing is created" do
    sign_in_as users(:client)

    assert_no_difference "Design.count" do
      post design_uploads_path, params: { design: valid_upload.except(:reference_image) }
      assert_response :unprocessable_entity

      post design_uploads_path, params: { design: valid_upload.merge(reference_rights_confirmed: "0") }
      assert_response :unprocessable_entity
    end
  end

  test "the picture is sent to the service's conversion, never to the generation" do
    design = upload_design
    stub_request(:post, CONVERT).to_return(status: 202, body: { job_id: "c1", job_ids: [ "c1" ], refinements_left: 0 }.to_json)

    GenerateDesignJob.perform_now(design)

    assert_requested :post, CONVERT do |request|
      body = JSON.parse(request.body)
      Base64.strict_decode64(body["image"]) == design.reference_image.download && body["title"] == design.prompt
    end
    assert_not_requested :post, "http://generator.test/generate"
    assert_predicate design.reload, :generating?
  end

  test "a picture sent as is cannot be redrawn by the AI" do
    design = upload_design
    design.update_columns(status: "ready", generator_job_id: "c1")
    sign_in_as users(:client)

    assert_no_difference "Design.count" do
      post design_variants_path(design)
      post design_refine_path(design), params: { instruction: "ajoute un chapeau" }
    end
    assert_not_requested :post, %r{generator\.test}
  end

  test "it does not count against the workshop's monthly generations" do
    printer = printers(:rennes)
    used = PrinterGenerationQuota.for(printer).used
    upload_design.update_columns(printer_id: printer.id)

    assert_equal used, PrinterGenerationQuota.for(printer).used
  end

  private
    def valid_upload
      { prompt: "Logo du club", technique: "dtf", print_width_cm: 25, remove_background: "1",
        reference_rights_confirmed: "1", ai_declared: "0",
        reference_image: upload(png(300, 200), "image/png", "logo.png") }
    end

    def upload_design
      design = Design.new(user: users(:client), mode: "upload", prompt: "Mon visuel", technique: "dtf",
                          print_width_cm: 25, reference_rights_confirmed: true)
      design.reference_image.attach(io: StringIO.new(png(300, 200)), filename: "image-de-depart.png",
                                    content_type: "image/png")
      design.save!
      design
    end

    def upload(bytes, type, name)
      Rack::Test::UploadedFile.new(StringIO.new(bytes), type, original_filename: name)
    end

    def png(width, height)
      Vips::Image.black(width, height).add(200).cast(:uchar).bandjoin([ 30, 40 ])
                 .copy(interpretation: :srgb).write_to_buffer(".png")
    end
end
