require "test_helper"

class PrinterDirectoryTest < ActiveSupport::TestCase
  RENNES = { latitude: "48.1173", longitude: "-1.6778" }.freeze

  test "with no filter, every published listing is offered" do
    assert_equal 3, directory({}).printers.size
    assert_not_includes directory({}).printers, printers(:brouillon)
    assert_not_includes directory({}).printers, printers(:attente)
  end

  test "featured listings lead" do
    assert_equal printers(:lyon), directory({}).printers.first
  end

  # The rule that shapes the whole directory: filtering by area must not hide
  # the shops that do not need to be nearby.
  test "a shop shipping nationwide survives a radius that excludes it" do
    result = directory(RENNES.merge(radius: 10))

    assert_includes result.printers, printers(:rennes)
    assert_includes result.printers, printers(:lyon), "Lyon ships across France"
    assert_not_includes result.printers, printers(:nantes)
  end

  test "a radius wide enough brings back the shops in between" do
    assert_includes directory(RENNES.merge(radius: 200)).printers, printers(:nantes)
  end

  test "an unknown radius falls back to the default rather than to nothing" do
    assert_equal PrinterDirectory::DEFAULT_RADIUS_KM, directory(RENNES.merge(radius: 7)).radius_km
  end

  test "coordinates that are not numbers are ignored, not fatal" do
    result = directory(latitude: "ici", longitude: "là")

    assert_not result.near?
    assert_equal 3, result.printers.size
  end

  test "searching narrows by name or town" do
    assert_equal [ printers(:rennes) ], directory(q: "Thabor").printers
    assert_equal [ printers(:lyon) ], directory(q: "lyon").printers
  end

  test "a department narrows without any geocoding" do
    assert_equal [ printers(:nantes) ], directory(department: "44").printers
  end

  test "filtering by technique keeps the shops that do it" do
    result = directory(techniques: %w[ embroidery ])

    assert_equal [ printers(:nantes) ], result.printers
  end

  test "several techniques widen rather than narrow" do
    result = directory(techniques: %w[ embroidery dtf ])

    assert_includes result.printers, printers(:nantes)
    assert_includes result.printers, printers(:lyon)
  end

  test "an unknown technique is dropped instead of emptying the results" do
    assert_equal 3, directory(techniques: %w[ lithographie ]).printers.size
  end

  test "service filters apply one by one" do
    assert_equal [ printers(:rennes) ], directory(pickup: "1").printers
    assert_equal [ printers(:nantes) ], directory(express_available: "1").printers
    assert_equal [ printers(:lyon) ], directory(ships: "1").printers
  end

  test "the textile label narrows the list" do
    assert_equal [ printers(:rennes) ], directory(textile_label: "gots").printers
  end

  test "an unknown label is ignored" do
    assert_equal 3, directory(textile_label: "inventé").printers.size
  end

  test "only located shops go on the map" do
    located = directory({}).located

    assert_equal 3, located.size
    assert located.all?(&:located?)
  end

  private
    def directory(filters)
      PrinterDirectory.call(scope: Printer.listed, filters: filters)
    end
end
