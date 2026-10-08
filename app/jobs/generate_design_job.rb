# Hands a design to the generation service and hands the waiting over to
# PollDesignJob.
#
# One click draws several proposals (SpawnProposals): the design this job was
# given asks for all of them in a single call, and each sibling still waiting
# receives one of the job ids that come back, in order.
#
# Everything that can go wrong here is something the client must be told about
# in their own words, so each failure ends with the design in `failed` and a
# sentence to read — never with a job silently retrying out of sight.
class GenerateDesignJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(design)
    return unless design.may_start?
    return convert(design) if design.upload?

    designs = [ design, *waiting_siblings(design) ]
    response = GeneratorClient.new.generate(design, count: designs.size)
    job_ids = Array(response["job_ids"].presence || response.fetch("job_id"))

    designs.each_with_index do |proposal, index|
      if job_ids[index]
        launch(proposal, job_ids[index], response["refinements_left"])
      else
        # The service drew fewer than asked — its own ceiling is lower. The
        # empty slot says so rather than spinning; the click is not refunded,
        # since the others went through.
        abandon(proposal, I18n.t("designs.errors.unavailable"))
      end
    end
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
    # The client's own image: one job, no siblings, no reprises. It cost no
    # generation, so a refusal refunds nothing.
    def convert(design)
      response = GeneratorClient.new.convert(design)
      launch(design, response.fetch("job_id"), nil)
    end

    # Le filet ne doit jamais masquer l'erreur qu'il attrape.
    def safely
      yield
    rescue StandardError => e
      Rails.logger.error("[generator] échec du filet lui-même : #{e.class} — #{e.message}")
    end

    def poll_interval = Rails.application.config.tshirt.generation[:poll_interval_seconds].seconds

    # The other proposals of the click, still without a job of their own.
    def waiting_siblings(design)
      return [] if design.batch_token.blank?

      Design.where(batch_token: design.batch_token, status: "pending")
            .where.not(id: design.id).order(:id).to_a
    end

    def launch(design, job_id, refinements_left)
      design.update!(generator_job_id: job_id, refinements_left: refinements_left)
      design.start!
      PollDesignJob.set(wait: poll_interval).perform_later(design)
    end

    # A generation that never started consumed nothing: the attempt goes back.
    #
    # Le design est rechargé pour la même raison que dans PollDesignJob : un
    # objet resté invalide en mémoire empêcherait de l'enregistrer comme
    # échoué, et l'écran du client tournerait sans fin.
    #
    # The whole click is refused at once — its waiting siblings with it — and
    # refunded once, since it was counted once.
    def refuse(design, message, refund:)
      GenerationQuota.for_user_id(design.user_id).refund! if refund && !design.upload?

      [ design, *waiting_siblings(design) ].each { |proposal| abandon(proposal, message) }
    end

    def abandon(design, message)
      fresh = Design.find(design.id)
      return unless fresh.may_fail?

      fresh.fail!(message)
      fresh.save!
      DesignChannel.broadcast(fresh)
    end
end
