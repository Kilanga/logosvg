require "test_helper"

# The sheet carries what the print file cannot. See docs/SPEC.md, "Fiche
# technique jointe à l'envoi".
class PrintRequestSheetTest < ActiveSupport::TestCase
  test "a vector job is described in inks, screens and palette" do
    lines = labels_and_values(print_requests(:waiting))

    assert_equal "Sérigraphie", lines[t("technique")]
    assert_equal "25 cm", lines[t("print_width")]
    assert_equal "3", lines[t("inks")].to_s
    assert_match "#1F5F7A", lines[t("palette")]
    assert_nil lines[t("resolution")], "pixels mean nothing on a screen-printed job"
  end

  test "a raster job is described in pixels, not in screens" do
    lines = labels_and_values(print_requests(:acknowledged))

    assert_equal "300 dpi", lines[t("resolution")]
    assert_equal "13 cm", lines[t("sharp_up_to")]
    assert_nil lines[t("inks")], "there are no screens to mount on a DTF press"
    assert_nil lines[t("palette")]
  end

  # What lets the same image be generated again months later.
  test "the sheet carries what would let the image be made again" do
    lines = labels_and_values(print_requests(:waiting))

    assert_equal designs(:fox_screen).prompt, lines[t("asked_for")]
    assert_equal designs(:fox_screen).prompt_used, lines[t("prompt_used")]
    assert_equal "123456", lines[t("seed")].to_s
    assert_equal "Mascotte", lines[t("style")]
  end

  test "the order itself is on the sheet, in the catalogue's size order" do
    lines = labels_and_values(print_requests(:waiting))

    assert_equal "M × 10   L × 5", lines[t("sizes")]
    assert_equal "15", lines[t("total_qty")].to_s
  end

  test "who supplies the textile is said in words, with the model and colour" do
    lines = labels_and_values(print_requests(:waiting))

    assert_match t("textile_source.printer"), lines[t("textile")]
    assert_match "Stanley Stella Creator", lines[t("textile")]
    assert_match "Noir", lines[t("textile")]
  end

  test "the placement is translated, not handed over as a database key" do
    lines = labels_and_values(print_requests(:waiting))

    assert_equal I18n.t("enums.printer.placements.chest_center"), lines[t("placements")]
  end

  # An empty line on a workshop's sheet is a question the workshop will ask.
  test "nothing empty reaches the sheet" do
    request = print_requests(:acknowledged)

    assert_predicate request.message, :blank?
    assert PrintRequestSheet.call(print_request: request).none? { |line| line.value.blank? }
  end

  test "a refinement instruction appears only when there was one" do
    assert_nil labels_and_values(print_requests(:waiting))[t("instruction")]

    designs(:fox_screen).update!(instruction: "un casque rouge", mode: "refine")
    # Found afresh: the fixture accessor hands back the request with its design
    # already loaded, instruction and all — as it was a moment ago.
    refined = PrintRequest.find(print_requests(:waiting).id)

    assert_equal "un casque rouge", labels_and_values(refined)[t("instruction")]
  end

  private
    def t(key) = I18n.t("print_requests.sheet.#{key}")

    def labels_and_values(print_request)
      PrintRequestSheet.call(print_request: print_request)
                       .to_h { |line| [ line.label, line.value ] }
    end
end
