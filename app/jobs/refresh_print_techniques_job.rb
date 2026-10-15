# Keeps the cached copy of the technique catalogue fresh.
#
# The only path by which the application asks the generation service for the
# catalogue. Everything else reads the cache, or the bundled copy — so a shop
# can always fill in its listing, even while the generation machine is off.
class RefreshPrintTechniquesJob < ApplicationJob
  queue_as :default

  # A stale catalogue is a small problem and an unreachable service is a normal
  # state here: the generation machine is a workstation behind a tunnel, not a
  # server. Retry a little, then let the next run take over — quietly: a
  # machine asleep for the night is not a failure to keep (reported on
  # 16/10/2026: 802 failed runs in the queue, every one of them this, which
  # buried anything else that might fail). Admin > État already says when the
  # service cannot be reached, and the catalogue says it is the bundled copy.
  retry_on GeneratorClient::Unavailable, wait: :polynomially_longer, attempts: 3 do |_job, error|
    Rails.logger.warn("[print_techniques] generation service unreachable, catalogue kept: #{error.message}")
  end

  # A refused key will not fix itself by being retried.
  discard_on GeneratorClient::Unauthorized do |_job, error|
    Rails.logger.error("[print_techniques] #{error.message}")
  end

  def perform
    forget_earlier_failures
    count = PrintTechniques.refresh!
    Rails.logger.info("[print_techniques] catalogue refreshed, #{count} techniques")
  end

  private
    # The runs that failed before 16/10/2026 stay in Solid Queue's failed list
    # until someone discards them. They say nothing the status page does not,
    # so each run clears its own kind — and only its own kind. Best effort: the
    # catalogue matters more than the housekeeping.
    def forget_earlier_failures
      return unless defined?(SolidQueue::FailedExecution)

      SolidQueue::FailedExecution
        .where(job_id: SolidQueue::Job.where(class_name: self.class.name).select(:id))
        .discard_all_in_batches
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("[print_techniques] could not clear earlier failures: #{e.class}")
    end
end
