require "test_helper"

class SendPrintRequestTest < ActiveSupport::TestCase
  setup do
    @design = designs(:fox_screen)
    attach_print_file
  end

  test "a compatible request is stamped, saved and mailed to both sides" do
    request = build_request

    assert_emails 2 do
      result = SendPrintRequest.call(print_request: request)

      assert_predicate result, :success?
    end

    assert_predicate request, :persisted?
    assert_predicate request, :sent?
    assert_not_nil request.sent_at
  end

  # The point of the whole object: what the workshop holds must not move when
  # the design does.
  test "the request takes its own copy of the print file" do
    request = build_request
    SendPrintRequest.call(print_request: request)

    assert_predicate request.final_file, :attached?
    assert_equal @design.print_file.filename.to_s, request.final_file.filename.to_s
    assert_not_equal @design.print_file.blob.id, request.final_file.blob.id,
                     "a shared blob would tie the workshop's copy to the design's"
  end

  test "deleting the design leaves the workshop's copy intact" do
    request = build_request
    SendPrintRequest.call(print_request: request)
    blob_id = request.final_file.blob.id

    @design.print_file.purge

    assert_predicate request.reload.final_file, :attached?
    assert_equal blob_id, request.final_file.blob.id
  end

  test "the watermarked preview travels too" do
    request = build_request
    SendPrintRequest.call(print_request: request)

    assert_predicate request.preview_png, :attached?
    assert_equal "image/png", request.preview_png.content_type
  end

  # The directory already said so on screen; sending anyway would waste both
  # sides' time.
  test "a shop that cannot do the job is never mailed" do
    request = build_request(printer: printers(:lyon))

    assert_no_emails do
      result = SendPrintRequest.call(print_request: request)

      assert_not_predicate result, :success?
      assert_predicate result.error, :present?
    end

    assert_not_predicate request, :persisted?
  end

  test "a design that is not ready is never sent" do
    pending = designs(:pending_design)
    request = build_request(design: pending, printer: printers(:rennes))

    assert_no_emails do
      result = SendPrintRequest.call(print_request: request)

      assert_not_predicate result, :success?
    end
  end

  test "the workshop's email carries the print file, the client's does not" do
    request = build_request
    SendPrintRequest.call(print_request: request)
    perform_enqueued_jobs

    to_printer = ActionMailer::Base.deliveries.find { |m| m.to.include?(printers(:rennes).orders_email) }
    to_client = ActionMailer::Base.deliveries.find { |m| m.to.include?(users(:client).email_address) }

    assert_includes to_printer.attachments.map(&:filename), "design.svg"
    assert_not_includes to_client.attachments.map(&:filename), "design.svg",
                        "the print file never reaches the client"
    assert to_client.attachments.any? { |a| a.filename.end_with?(".png") },
           "the client gets the watermarked preview instead"
  end

  private
    def attach_print_file
      @design.print_file.attach(
        io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml"
      )
    end

    def build_request(**attributes)
      PrintRequest.new({
        design: @design,
        client: users(:client),
        printer: printers(:rennes),
        print_width_cm: @design.print_width_cm,
        sizes: { "M" => "20" },
        contact_name: "Claire Martin",
        contact_email: "claire@example.invalid",
        consent_text_version: "2026-09-v1",
        consented_at: Time.current
      }.merge(attributes))
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 10 10">) +
        %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>)
    end
end
