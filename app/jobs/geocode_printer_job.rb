# Places a shop on the map after its address changes.
#
# Writes with update_columns on purpose: coordinates are derived data, not
# something the printer filled in. Going through the model would re-run
# validations and, worse, re-trigger this very job.
class GeocodePrinterJob < ApplicationJob
  queue_as :default

  # A shop with no pin is missing from the map, so it is worth retrying — but
  # not forever, and never loudly.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(printer)
    result = Geocoding.call(printer.full_address)

    printer.update_columns(
      { latitude: result.latitude, longitude: result.longitude, updated_at: Time.current }
        .merge(official_city(printer, result))
    )
  end

  private
    # The town as the Base Adresse Nationale writes it, when it is the same
    # town as the one typed — differing only in capitals, hyphens or accents
    # (reported on 14/10/2026: « Satolas Et bonce » for Satolas-et-Bonce). A
    # different town is a different answer, and the shop's own word stands.
    def official_city(printer, result)
      return {} if result.city.blank? || printer.city.blank? || result.city == printer.city
      return {} unless result.city.parameterize == printer.city.parameterize

      { city: result.city }
    end
end
