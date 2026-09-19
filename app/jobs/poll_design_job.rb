# Asks the service whether a design is ready, and re-schedules itself until it
# is — for five minutes at most.
#
# Re-scheduling rather than sleeping: a worker that sleeps for five minutes is a
# worker that is not doing anything else, and this application generates in
# minutes, not seconds.
class PollDesignJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(design, started_at: Time.current)
    return unless design.generating?

    if timed_out?(started_at)
      return give_up(design, I18n.t("designs.errors.timed_out"))
    end

    answer = GeneratorClient.new.job(design.generator_job_id, user: design.user)

    case answer["status"]
    when "done"  then complete(design, answer)
    when "error" then give_up(design, answer["error"].presence || I18n.t("designs.errors.failed"))
    else reschedule(design, started_at)
    end
  rescue GeneratorClient::NotFound
    # The job has expired off the generation machine, which keeps files for an
    # hour. Nothing left to wait for.
    give_up(design, I18n.t("designs.errors.expired"))
  rescue GeneratorClient::Unavailable => e
    # The tunnel drops, the workstation sleeps: worth waiting through, up to the
    # same five minutes as everything else.
    Rails.logger.info("[generator] #{e.message}, still waiting for #{design.token}")
    reschedule(design, started_at)
  end

  private
    def settings = Rails.application.config.tshirt.generation

    def timed_out?(started_at) = Time.current - started_at > settings[:poll_timeout_seconds]

    def reschedule(design, started_at)
      self.class.set(wait: settings[:poll_interval_seconds].seconds)
                .perform_later(design, started_at: started_at)
    end

    def complete(design, answer)
      StoreGeneratedDesign.call(design: design, answer: answer)
    rescue StoreGeneratedDesign::UnusableFile => e
      # The service produced something we will not serve. The client is told,
      # and the attempt is handed back: the fault is not theirs.
      Rails.logger.error("[generator] #{e.message} for #{design.token}")
      give_up(design, I18n.t("designs.errors.unusable_file"))
    end

    def give_up(design, message)
      GenerationQuota.for(design.user).refund!
      design.fail!(message)
      design.save!
      DesignChannel.broadcast(design)
    end
end
