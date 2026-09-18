require "test_helper"

# The three ways a shop can be unable to print a design, and the two families of
# technique. Written before any Design exists: step 3 plugs a real design into
# the same call.
class PrinterCompatibilityTest < ActiveSupport::TestCase
  test "a shop that practises the technique and fits the limits can print" do
    result = check(printers(:rennes), technique: "screen_printing", inks_count: 3, print_width_cm: 25)

    assert_predicate result, :compatible?
    assert_nil result.reason
  end

  # First question, and the one that settles most cases: other machines do not
  # help if none of them is the one asked for.
  test "a shop that does not practise the technique is out, whatever else it owns" do
    result = check(printers(:rennes), technique: "dtf", inks_count: 3)

    assert_not_predicate result, :compatible?
    assert_equal :technique_not_practised, result.reason
    assert_equal "ne pratique pas DTF", result.message
  end

  test "too many inks for a technique that counts them" do
    result = check(printers(:nantes), technique: "flex", inks_count: 4)

    assert_not_predicate result, :compatible?
    assert_equal :too_many_inks, result.reason
    assert_equal "2 encres maximum, le design en compte 4", result.message
  end

  test "the ceiling agrees in the singular too" do
    printer_techniques(:nantes_flex).update!(max_colors: 1)

    assert_equal "1 encre maximum, le design en compte 4",
                 check(printers(:nantes), technique: "flex", inks_count: 4).message
  end

  test "an ink count is never held against a machine that prints every colour at once" do
    result = check(printers(:lyon), technique: "dtf", inks_count: 24)

    assert_predicate result, :compatible?
  end

  test "a design wider than the technique allows" do
    result = check(printers(:nantes), technique: "embroidery", inks_count: 2, print_width_cm: 30)

    assert_not_predicate result, :compatible?
    assert_equal :too_wide, result.reason
    assert_equal "largeur maximale 20 cm", result.message
  end

  test "width falls back to the listing's maximum when the technique states none" do
    result = check(printers(:nantes), technique: "flex", inks_count: 2, print_width_cm: 500)

    assert_not_predicate result, :compatible?
    assert_equal :too_wide, result.reason
  end

  test "a design that states no size is not judged on size" do
    assert_predicate check(printers(:nantes), technique: "embroidery", inks_count: 2), :compatible?
  end

  # The technique is asked first because it decides fastest and reads best: a
  # client told "2 inks maximum" about a shop that does not do flex at all would
  # be misled.
  test "the technique is answered before the ink count" do
    result = check(printers(:lyon), technique: "flex", inks_count: 40)

    assert_equal :technique_not_practised, result.reason
  end

  test "a whole list is judged in one pass" do
    results = PrinterCompatibility.for_each(
      [ printers(:rennes), printers(:lyon), printers(:nantes) ],
      technique: "screen_printing", inks_count: 3
    )

    assert_predicate results[printers(:rennes)], :compatible?
    assert_not_predicate results[printers(:lyon)], :compatible?
    assert_not_predicate results[printers(:nantes)], :compatible?
  end

  private
    def check(printer, **options) = PrinterCompatibility.call(printer: printer, **options)
end
