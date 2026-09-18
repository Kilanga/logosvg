# Builds the printer directory from the filters a visitor submitted.
#
# One rule shapes the whole thing: a shop that delivers across France stays in
# the results even when it sits outside the search radius. Filtering by area
# would otherwise hide exactly the shops that do not need to be nearby.
class PrinterDirectory
  DEFAULT_RADIUS_KM = 50
  RADII_KM = [ 10, 25, 50, 100, 200 ].freeze
  LIMIT = 120

  BOOLEAN_FILTERS = %w[ express_available pickup ships provides_textile accepts_client_textile ].freeze

  Result = Data.define(:printers, :filters, :center, :radius_km) do
    def located = printers.select(&:located?)
    def any? = printers.any?
    def near? = center.present?
  end

  def self.call(scope:, filters:) = new(scope: scope, filters: filters).call

  def initialize(scope:, filters:)
    @scope = scope
    @filters = filters
  end

  def call
    relation = @scope.includes(:techniques).with_attached_logo

    relation = apply_search(relation)
    relation = apply_area(relation)
    relation = apply_techniques(relation)
    relation = apply_booleans(relation)
    relation = apply_label(relation)

    Result.new(
      printers: relation.by_prominence.limit(LIMIT).to_a,
      filters: @filters,
      center: center,
      radius_km: radius_km
    )
  end

  private
    def apply_search(relation)
      term = @filters[:q]
      term.present? ? relation.matching(term) : relation
    end

    # Either a radius around coordinates the browser provided, or a department
    # typed by hand. Never a geocoding call: this runs inside a request.
    def apply_area(relation)
      if center
        nearby = relation.within_km(latitude: center[:latitude], longitude: center[:longitude], radius: radius_km)
        relation.where(id: nearby.select(:id)).or(relation.where(ships: true))
      elsif @filters[:department].present?
        relation.in_department(@filters[:department])
      else
        relation
      end
    end

    def apply_techniques(relation)
      wanted = Array(@filters[:techniques]).select { |t| PrinterTechnique.techniques.key?(t) }
      return relation if wanted.empty?

      relation.where(id: PrinterTechnique.where(technique: wanted).select(:printer_id))
    end

    def apply_booleans(relation)
      BOOLEAN_FILTERS.reduce(relation) do |scoped, name|
        @filters[name.to_sym].present? ? scoped.where(name => true) : scoped
      end
    end

    def apply_label(relation)
      label = @filters[:textile_label]
      return relation unless Printer.textile_labels.key?(label)

      relation.where(textile_label: label)
    end

    def center
      @center ||= begin
        latitude = Float(@filters[:latitude], exception: false)
        longitude = Float(@filters[:longitude], exception: false)

        { latitude: latitude, longitude: longitude } if latitude && longitude
      end
    end

    def radius_km
      value = @filters[:radius].to_i
      RADII_KM.include?(value) ? value : DEFAULT_RADIUS_KM
    end
end
