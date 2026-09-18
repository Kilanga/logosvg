# The catalogue of printing techniques, as the microservice defines it.
#
# The service is authoritative — it is the thing that actually generates the
# file, and the only place that knows a sublimation print is a raster at 300 dpi.
# The application keeps a cached copy so a form can be rendered without waiting
# on another machine, and never a second definition.
#
# Reading is never a network call. A background job refreshes the cache; a cache
# miss falls back to the copy in config/print_techniques.yml. A page therefore
# renders whether or not the generation machine is awake.
class PrintTechniques
  CACHE_KEY = "print_techniques/catalogue"
  CACHE_TTL = 1.hour
  FALLBACK_PATH = Rails.root.join("config/print_techniques.yml")

  # A key the catalogue does not know is a configuration fault — a stale copy, a
  # renamed technique — not something a visitor typed.
  UnknownTechnique = Class.new(StandardError)

  Technique = Data.define(:key, :label, :family, :max_colors, :default_colors,
                          :gradients, :white_is_ink, :dpi, :file_name) do
    def vector? = family == "vector"
    def raster? = family == "raster"

    # Techniques applied one colour at a time: every ink is a screen, a vinyl
    # cut or a thread, and the shop has a ceiling. The others print a full image.
    def limited_colors? = max_colors.present?

    def native_format = file_name.split(".").last
  end

  class << self
    def all = catalogue.values

    def keys = catalogue.keys

    def find(key) = catalogue[key.to_s]

    def fetch(key)
      find(key) || raise(UnknownTechnique, "unknown printing technique: #{key.inspect}")
    end

    def label_for(key) = find(key)&.label || key.to_s

    # Called by RefreshPrintTechniquesJob. The only place that reaches the
    # network.
    def refresh!
      entries = GeneratorClient.techniques
      Rails.cache.write(CACHE_KEY, entries, expires_in: CACHE_TTL)
      reset!
      entries.size
    end

    # Drops the per-request memo. Tests use it after stubbing the catalogue.
    def reset!
      RequestStore.clear
    end

    private
      def catalogue
        RequestStore.fetch { build(Rails.cache.read(CACHE_KEY) || fallback_entries) }
      end

      def build(entries)
        entries.to_h do |entry|
          attributes = entry.symbolize_keys
          [ attributes[:key], Technique.new(**attributes.slice(*Technique.members)) ]
        end
      end

      def fallback_entries
        Rails.logger.info("[print_techniques] catalogue not cached, using the bundled copy")
        YAML.load_file(FALLBACK_PATH).fetch("techniques")
      end
  end

  # One catalogue per request rather than one per call: a listing form asks for
  # it a dozen times, and the cache store is not free either.
  module RequestStore
    KEY = :print_techniques_catalogue

    def self.fetch(&block) = ActiveSupport::IsolatedExecutionState[KEY] ||= block.call

    def self.clear = ActiveSupport::IsolatedExecutionState.delete(KEY)
  end
end
