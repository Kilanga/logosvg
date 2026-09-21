# Hands a design to the generation service and hands the waiting over to
# PollDesignJob.
#
# Everything that can go wrong here is something the client must be told about
# in their own words, so each failure ends with the design in `failed` and a
# sentence to read — never with a job silently retrying out of sight.
class GenerateDesignJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(design)
    return unless design.may_start?

    response = GeneratorClient.new.generate(design)

    design.update!(
      generator_job_id: response.fetch("job_id"),
      refinements_left: response["refinements_left"]
    )
    design.start!

    PollDesignJob.set(wait: poll_interval).perform_later(design)
  rescue GeneratorClient::Rejected => e
    # A blocked term or an unusable prompt: the service's own sentence is the
    # most useful thing the client can read.
    refuse(design, e.detail, refund: true)
  rescue GeneratorClient::RateLimited => e
    refuse(design, I18n.t("designs.errors.rate_limited", minutes: (e.retry_after.to_i / 60) + 1),
           refund: true)
  rescue GeneratorClient::Unauthorized
    # A misconfigured key is our fault, and saying so to the client would mean
    # nothing to them.
    Rails.logger.error("[generator] the service refused our API key")
    refuse(design, I18n.t("designs.errors.unavailable"), refund: true)
  rescue GeneratorClient::Unavailable => e
    Rails.logger.warn("[generator] #{e.message}")
    refuse(design, I18n.t("designs.errors.unavailable"), refund: true)
  rescue StandardError => e
    # Le filet. Une panne que ce travail n'avait pas prévue — un bogue de notre
    # côté — laissait le design en `pending` pour toujours : la file enregistre
    # l'échec, mais le client, lui, regarde un écran qui tourne et ne saura
    # jamais que plus rien n'arrive. Le design est donc marqué échoué et rendu,
    # puis l'erreur repart : elle est notre affaire, pas la sienne, et elle doit
    # rester visible dans la file.
    Rails.logger.error("[generator] panne imprévue : #{e.class} — #{e.message}")
    safely { refuse(design, I18n.t("designs.errors.failed"), refund: true) }
    raise
  end

  private
    # Le filet ne doit jamais masquer l'erreur qu'il attrape.
    def safely
      yield
    rescue StandardError => e
      Rails.logger.error("[generator] échec du filet lui-même : #{e.class} — #{e.message}")
    end

    def poll_interval = Rails.application.config.tshirt.generation[:poll_interval_seconds].seconds

    # A generation that never started consumed nothing: the attempt goes back.
    def refuse(design, message, refund:)
      GenerationQuota.for_user_id(design.user_id).refund! if refund
      design.fail!(message)
      design.save!
      DesignChannel.broadcast(design)
    end
end
