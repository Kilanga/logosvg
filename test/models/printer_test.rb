require "test_helper"

class PrinterTest < ActiveSupport::TestCase
  test "a listing needs a name and an orders address" do
    printer = Printer.new(user: users(:client))

    assert_not printer.valid?
    assert printer.errors.include?(:name)
    assert printer.errors.include?(:orders_email)
  end

  test "the slug comes from the name" do
    printer = build_printer(name: "Sérigraphie de l'Île")

    assert printer.save
    assert_equal "serigraphie-de-l-ile", printer.slug
  end

  test "two shops with the same name get distinct slugs" do
    printer = build_printer(name: printers(:rennes).name)

    assert printer.save
    assert_equal "#{printers(:rennes).slug}-2", printer.slug
  end

  test "public urls carry the slug, never the id" do
    assert_equal printers(:rennes).slug, printers(:rennes).to_param
  end

  test "the orders address is stored lowercased" do
    printer = build_printer(orders_email: "  Commandes@Atelier.FR ")

    assert printer.save
    assert_equal "commandes@atelier.fr", printer.orders_email
  end

  test "a draft may be incomplete, a published listing may not" do
    printer = printers(:brouillon)

    assert_predicate printer, :valid?

    printer.status = :published

    assert_not printer.valid?
    assert printer.errors.include?(:address)
    assert printer.errors.include?(:city)
    assert printer.errors.include?(:description)
  end

  test "a postal code is five digits" do
    assert_not build_printer(postal_code: "3500").valid?
    assert build_printer(postal_code: "35000").valid?
  end

  test "a brand colour is a hex triplet" do
    assert_not build_printer(brand_color: "bleu").valid?
    assert build_printer(brand_color: "#1F5F7A").valid?
  end

  test "only published listings are in the directory" do
    listed = Printer.listed

    assert_includes listed, printers(:rennes)
    assert_not_includes listed, printers(:brouillon)
    assert_not_includes listed, printers(:attente)
  end

  test "the radius keeps what is inside and drops what is not" do
    near_rennes = Printer.listed.within_km(latitude: 48.1173, longitude: -1.6778, radius: 50)

    assert_includes near_rennes, printers(:rennes)
    assert_not_includes near_rennes, printers(:nantes), "Nantes is about 107 km away"
    assert_not_includes near_rennes, printers(:lyon)
  end

  test "a wider radius reaches further" do
    wide = Printer.listed.within_km(latitude: 48.1173, longitude: -1.6778, radius: 200)

    assert_includes wide, printers(:nantes)
  end

  test "searching matches a name or a town" do
    assert_includes Printer.matching("thabor"), printers(:rennes)
    assert_includes Printer.matching("lyon"), printers(:lyon)
    assert_empty Printer.matching("introuvable")
  end

  test "a department is the first two digits of the postal code" do
    assert_includes Printer.in_department("35"), printers(:rennes)
    assert_not_includes Printer.in_department("35"), printers(:nantes)
  end

  test "featured listings come first when no search centre is known" do
    assert_equal printers(:lyon), Printer.listed.by_prominence.first
  end

  # Lyon is featured, but some 700 km from Rennes — a national lead would send
  # a Rennes client to a shop that cannot serve them any faster than the rest.
  # Nobody is both featured and close here, so the fallback is the same plain
  # alphabetical order as when nobody is featured at all.
  test "a featured shop leads only within reach of a known search centre" do
    rennes_centre = { latitude: printers(:rennes).latitude, longitude: printers(:rennes).longitude }

    ordered = Printer.listed.by_prominence(near: rennes_centre).to_a

    assert_not_equal printers(:lyon), ordered.first
    assert_equal ordered.sort_by(&:name), ordered, "alphabetical, since nobody is prominent here"
  end

  test "a featured shop leads once the search centre is close enough to it" do
    printers(:rennes).update!(featured: true)
    rennes_centre = { latitude: printers(:rennes).latitude, longitude: printers(:rennes).longitude }

    assert_equal printers(:rennes), Printer.listed.by_prominence(near: rennes_centre).first
  end

  test "prominence follows the plan, then distance, never the reverse" do
    near = { latitude: printers(:lyon).latitude, longitude: printers(:lyon).longitude }

    assert printers(:lyon).prominent?(near: near), "featured, and right at the centre"
    assert printers(:lyon).prominent?, "without a centre, the plan alone decides"
    assert_not printers(:rennes).prominent?(near: near), "not featured at all"
  end

  test "a featured shop stops being prominent beyond the radius" do
    rennes_centre = { latitude: printers(:rennes).latitude, longitude: printers(:rennes).longitude }

    assert_not printers(:lyon).prominent?(near: rennes_centre), "featured, but 700 km away"
  end

  test "distance is measured in kilometres, both ways" do
    rennes = printers(:rennes)
    nantes_point = { latitude: printers(:nantes).latitude, longitude: printers(:nantes).longitude }

    distance = rennes.distance_km_to(nantes_point)

    assert_in_delta 107, distance, 10
  end

  test "an unlocated shop has no distance to anyone" do
    rennes_point = { latitude: printers(:rennes).latitude, longitude: printers(:rennes).longitude }

    assert_nil printers(:brouillon).distance_km_to(rennes_point)
  end

  test "a shop knows which techniques it practises" do
    assert printers(:rennes).practises?("screen_printing")
    assert_not printers(:rennes).practises?("dtf")
    assert_equal %w[ embroidery flex sublimation ], printers(:nantes).technique_keys.sort
  end

  test "the primary technique is the one kept when a client does not know" do
    assert_equal "screen_printing", printers(:rennes).primary_technique.technique
    assert_equal "embroidery", printers(:nantes).primary_technique.technique
  end

  test "a listing designates exactly one primary technique" do
    printer = printers(:nantes)

    printer.techniques.each { |t| t.primary = true }
    assert_not printer.valid?
    assert printer.errors.include?(:techniques)

    printer.techniques.each { |t| t.primary = false }
    assert_not printer.valid?
  end

  test "a listing with no technique cannot leave the draft" do
    printer = printers(:brouillon)
    printer.assign_attributes(address: "2 rue du Change", postal_code: "37000",
                              city: "Tours", description: "Sérigraphie.", status: :published)

    assert_not printer.valid?
    assert printer.errors.include?(:techniques)
  end

  test "brands are typed as one line and stored as a list" do
    printer = printers(:rennes)

    printer.textile_brands_list = "Stanley/Stella, Continental , "

    assert_equal [ "Stanley/Stella", "Continental" ], printer.textile_brands
    assert_equal "Stanley/Stella, Continental", printer.textile_brands_list
  end

  test "changing the address sends the shop back to be geocoded" do
    assert_enqueued_with job: GeocodePrinterJob do
      printers(:rennes).update!(address: "4 place Sainte-Anne")
    end
  end

  test "changing something else does not" do
    assert_no_enqueued_jobs only: GeocodePrinterJob do
      printers(:rennes).update!(price_note: "À partir de 9 € la pièce")
    end
  end

  test "a shop with no coordinates is absent from the map" do
    assert_not_predicate printers(:brouillon), :located?
    assert_predicate printers(:rennes), :located?
    assert_not_includes Printer.located, printers(:brouillon)
  end

  private
    def build_printer(**attributes)
      Printer.new({
        user: users(:client),
        name: "Nouvel Atelier",
        orders_email: "nouveau@example.invalid"
      }.merge(attributes))
    end
end
