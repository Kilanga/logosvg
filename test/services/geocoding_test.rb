require "test_helper"

class GeocodingTest < ActiveSupport::TestCase
  SEARCH = %r{\Ahttps://data\.geopf\.fr/geocodage/search}

  setup { Geocoder::Lookup::Test.reset }

  test "an address the Base Adresse Nationale knows becomes coordinates" do
    stub_ban(score: 0.96)

    result = Geocoding.call("12 rue de Paris, 35000 Rennes")

    assert_predicate result, :found?
    assert_in_delta 48.1173, result.latitude, 0.0001
    assert_in_delta(-1.6778, result.longitude, 0.0001)
    assert_equal "12 Rue de Paris 35000 Rennes", result.label
  end

  test "an address it does not know yields nothing rather than a wrong pin" do
    stub_request(:get, SEARCH).to_return(
      body: { type: "FeatureCollection", features: [] }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    assert_not_predicate Geocoding.call("12 rue Introuvable, 00000 Nulle Part"), :found?
  end

  # The BAN answers "Rennes, somewhere" for a street it does not have. A pin in
  # the middle of town is worse than no pin at all.
  test "a poor match is refused" do
    stub_ban(score: 0.2)

    assert_not_predicate Geocoding.call("rue qui n'existe pas, Rennes"), :found?
  end

  test "an empty address never leaves the application" do
    assert_not_predicate Geocoding.call(""), :found?
    assert_not_requested :get, SEARCH
  end

  test "the service being unreachable yields nothing rather than raising" do
    stub_request(:get, SEARCH).to_timeout

    assert_nothing_raised do
      assert_not_predicate Geocoding.call("12 rue de Paris, 35000 Rennes"), :found?
    end
  end

  private
    def stub_ban(score:)
      stub_request(:get, SEARCH).to_return(
        body: {
          type: "FeatureCollection",
          features: [ {
            type: "Feature",
            geometry: { type: "Point", coordinates: [ -1.6778, 48.1173 ] },
            properties: { label: "12 Rue de Paris 35000 Rennes", score: score, city: "Rennes" }
          } ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    end
end
