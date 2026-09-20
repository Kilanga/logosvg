# Places a designer on the map after their city changes.
#
# Same reasoning as GeocodePrinterJob: `update_columns` because coordinates are
# derived data, and going through the model would re-trigger this very job.
class GeocodeDesignerProfileJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(profile)
    return if profile.city.blank?

    result = Geocoding.call([ profile.city, "France" ].join(", "))

    profile.update_columns(
      latitude: result.latitude,
      longitude: result.longitude,
      updated_at: Time.current
    )
  end
end
