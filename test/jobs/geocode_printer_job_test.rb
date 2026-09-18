require "test_helper"

class GeocodePrinterJobTest < ActiveJob::TestCase
  SEARCH = %r{\Ahttps://data\.geopf\.fr/geocodage/search}

  test "a shop with a known address lands on the map" do
    stub_request(:get, SEARCH).to_return(
      body: {
        features: [ {
          geometry: { coordinates: [ 3.0573, 50.6292 ] },
          properties: { label: "5 Rue Nationale 59000 Lille", score: 0.95 }
        } ]
      }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    printer = printers(:brouillon)
    printer.update_columns(address: "5 rue Nationale", postal_code: "59000", city: "Lille")

    GeocodePrinterJob.perform_now(printer)

    assert_in_delta 50.6292, printer.reload.latitude.to_f, 0.0001
    assert_in_delta 3.0573, printer.longitude.to_f, 0.0001
  end

  # Coordinates are derived data. Writing them through the model would re-run
  # validations on a possibly incomplete draft, and re-trigger this very job.
  test "a draft too incomplete to save is still placed on the map" do
    stub_request(:get, SEARCH).to_return(
      body: { features: [ { geometry: { coordinates: [ 3.0, 50.0 ] },
                            properties: { score: 0.9 } } ] }.to_json
    )

    printer = printers(:brouillon)
    printer.update_columns(address: "2 rue du Change", postal_code: "37000", city: "Tours")

    assert_nothing_raised { GeocodePrinterJob.perform_now(printer) }
    assert_predicate printer.reload, :located?
    assert_predicate printer, :draft?, "the listing is still too incomplete to publish"
  end

  test "an address that cannot be placed clears the old pin rather than keeping a wrong one" do
    stub_request(:get, SEARCH).to_return(body: { features: [] }.to_json)

    printer = printers(:rennes)
    assert_predicate printer, :located?

    GeocodePrinterJob.perform_now(printer)

    assert_not_predicate printer.reload, :located?
  end

  test "geocoding does not queue itself again" do
    stub_request(:get, SEARCH).to_return(body: { features: [] }.to_json)

    assert_no_enqueued_jobs only: GeocodePrinterJob do
      GeocodePrinterJob.perform_now(printers(:rennes))
    end
  end
end
