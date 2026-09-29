require "test_helper"

# Whether a request confirms the shop's own funnel — the link or QR code held
# all the way through — or found the shop some other way, most often the
# directory, for a design a different shop's link produced.
class PrintRequestOriginTest < ActiveSupport::TestCase
  test "a request sent to the shop that generated the design is from that shop's link" do
    request = print_requests(:acknowledged) # design fox_dtf, printer lyon — both lyon

    assert_includes PrintRequest.from_designs_printer, request
  end

  test "a request sent to a different shop than the one the design was made for is not" do
    request = print_requests(:found_in_directory) # design fox_screen (rennes), sent to lyon

    assert_not_includes PrintRequest.from_designs_printer, request
  end

  test "a design made with no shop in context never counts as from a link" do
    design = designs(:pending_design) # printer: nil
    design.update!(status: "ready", print_format: "svg")
    request = PrintRequest.new(
      design: design, client: users(:client), printer: printers(:rennes),
      textile_source: "printer", placements: [ "chest_center" ], print_width_cm: 25,
      sizes: { "M" => 5 }, total_qty: 5, contact_name: "Claire Martin",
      contact_email: "claire@example.invalid", consent_text_version: "2026-09-v1",
      consented_at: Time.current
    )
    request.save!(validate: false)

    assert_not_includes PrintRequest.from_designs_printer, request
  end
end
