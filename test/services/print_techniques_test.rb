require "test_helper"

class PrintTechniquesTest < ActiveSupport::TestCase
  CATALOGUE = %r{\Ahttps?://[^/]+/techniques\z}

  setup do
    PrintTechniques.reset!
    # The service has no address in the test environment, and the fallback path
    # is precisely what most of these tests exercise.
    ENV["GENERATOR_URL"] = "http://generator.test"
    # The suite runs on the null store, where a write is a no-op — which is the
    # one thing these tests need to observe.
    @cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    PrintTechniques.reset!
    Rails.cache = @cache
    ENV.delete("GENERATOR_URL")
  end

  # The point of the fallback: a shop fills in its listing whether or not the
  # generation machine is awake.
  test "reading the catalogue never touches the network" do
    assert_equal 6, PrintTechniques.all.size
    assert_not_requested :get, CATALOGUE
  end

  test "the bundled copy carries the six techniques and both families" do
    assert_equal %w[ screen_printing flex embroidery dtf dtg sublimation ].sort,
                 PrintTechniques.keys.sort

    assert_predicate PrintTechniques.fetch("screen_printing"), :vector?
    assert_predicate PrintTechniques.fetch("dtf"), :raster?
  end

  test "techniques that count their inks are the ones with a ceiling" do
    limited, unlimited = PrintTechniques.all.partition(&:limited_colors?)

    assert_equal %w[ embroidery flex screen_printing ], limited.map(&:key).sort
    assert_equal %w[ dtf dtg sublimation ], unlimited.map(&:key).sort
  end

  test "the native format follows the family" do
    assert_equal "svg", PrintTechniques.fetch("screen_printing").native_format
    assert_equal "png", PrintTechniques.fetch("sublimation").native_format
  end

  # A key the catalogue does not know means a stale copy or a renamed technique,
  # not something a visitor typed — so it raises rather than returning nil.
  test "an unknown key raises" do
    assert_raises PrintTechniques::UnknownTechnique do
      PrintTechniques.fetch("lithographie")
    end

    assert_nil PrintTechniques.find("lithographie"), "#find answers softly for callers that can cope"
  end

  test "refreshing reads the service and caches what it answers" do
    stub_request(:get, CATALOGUE).to_return(
      body: { techniques: [ catalogue_entry ] }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    assert_equal 1, PrintTechniques.refresh!
    assert_equal [ catalogue_entry ], Rails.cache.read(PrintTechniques::CACHE_KEY)
  end

  test "the cached catalogue wins over the bundled copy" do
    Rails.cache.write(PrintTechniques::CACHE_KEY, [ catalogue_entry ])
    PrintTechniques.reset!

    assert_equal [ "flocage_maison" ], PrintTechniques.keys
  end

  test "a service that refuses the key raises rather than caching nothing" do
    stub_request(:get, CATALOGUE).to_return(status: 401)

    assert_raises(GeneratorClient::Unauthorized) { PrintTechniques.refresh! }
  end

  test "a service that does not answer raises for the job to retry" do
    stub_request(:get, CATALOGUE).to_timeout

    assert_raises(GeneratorClient::Unavailable) { PrintTechniques.refresh! }
  end

  private
    def catalogue_entry
      {
        "key" => "flocage_maison", "label" => "Flocage maison", "family" => "vector",
        "max_colors" => 3, "default_colors" => 2, "gradients" => false,
        "white_is_ink" => false, "dpi" => 300, "file_name" => "design.svg"
      }
    end
end
