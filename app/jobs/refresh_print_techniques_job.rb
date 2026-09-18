# Keeps the cached copy of the technique catalogue fresh.
#
# The only path by which the application asks the generation service for the
# catalogue. Everything else reads the cache, or the bundled copy — so a shop
# can always fill in its listing, even while the generation machine is off.
class RefreshPrintTechniquesJob < ApplicationJob
  queue_as :default

  # A stale catalogue is a small problem and an unreachable service is a normal
  # state here: the generation machine is a workstation behind a tunnel, not a
  # server. Retry a little, then let the next run take over.
  retry_on GeneratorClient::Unavailable, wait: :polynomially_longer, attempts: 3

  # A refused key will not fix itself by being retried.
  discard_on GeneratorClient::Unauthorized do |_job, error|
    Rails.logger.error("[print_techniques] #{error.message}")
  end

  def perform
    count = PrintTechniques.refresh!
    Rails.logger.info("[print_techniques] catalogue refreshed, #{count} techniques")
  end
end
