require "test_helper"

class PrintersHelperTest < ActionView::TestCase
  test "only the first placement keeps its capital when several are joined" do
    characteristics = printer_characteristics(printers(:rennes))

    assert_includes characteristics[:printing], [
      I18n.t("activerecord.attributes.printer.placements"),
      "Poitrine, centré et dos, grand format"
    ]
  end

  test "a single placement is left exactly as its own label reads" do
    printers(:rennes).update!(placements: [ "chest_center" ])

    characteristics = printer_characteristics(printers(:rennes))

    assert_includes characteristics[:printing], [
      I18n.t("activerecord.attributes.printer.placements"),
      "Poitrine, centré"
    ]
  end
end
