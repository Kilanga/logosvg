# Turns a French postal address into coordinates, through the Base Adresse
# Nationale. The only place in the application that knows Geocoder exists.
#
# Called from background jobs: a directory that cannot be geocoded is a listing
# without a pin, never a request that hangs.
class Geocoding
  # Below this, the Base Adresse Nationale matched something far from what was
  # asked — usually just the town for a street it does not know. Placing a pin
  # on that would mislead more than showing none.
  MINIMUM_SCORE = 0.4

  Result = Data.define(:latitude, :longitude, :label, :score) do
    def found? = latitude.present? && longitude.present?
  end

  NOT_FOUND = Result.new(latitude: nil, longitude: nil, label: nil, score: nil)

  def self.call(address) = new(address).call

  def initialize(address)
    @address = address
  end

  def call
    return NOT_FOUND if @address.blank?

    # Geocoder wraps the whole GeoJSON collection in one result, so `#result`
    # is the best match rather than `.first` being it. An address the service
    # does not know yields a collection with no features at all.
    match = Geocoder.search(@address).first
    feature = match&.result
    return NOT_FOUND if feature.blank?

    properties = feature["properties"] || {}
    score = properties["score"]
    return NOT_FOUND if score.present? && score < MINIMUM_SCORE

    Result.new(
      latitude: match.latitude,
      longitude: match.longitude,
      label: properties["label"],
      score: score
    )
  rescue Geocoder::Error, Timeout::Error, SocketError, SystemCallError => e
    Rails.logger.warn("[geocoding] #{e.class}: #{e.message}")
    NOT_FOUND
  end
end
