# Addresses are geocoded through the French government's Base Adresse
# Nationale: free, no API key, and authoritative for the only country this
# platform serves.
#
# The spec asked to check the service's current address. It has moved: the
# historical api-adresse.data.gouv.fr still answers, but Geocoder's
# :ban_data_gouv_fr lookup now targets the Géoplateforme endpoint
# data.geopf.fr, which is the one to stub in tests. Both were queried with the
# same address and returned identical coordinates.
Geocoder.configure(
  lookup: :ban_data_gouv_fr,
  # A postal address is personal data: it does not travel in clear text.
  use_https: true,
  units: :km,
  timeout: 5,
  # Geocoding runs in a background job, so a failure is logged and retried
  # rather than raised into a request.
  always_raise: []
)
