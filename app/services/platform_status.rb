# What an administrator checks when something looks wrong.
#
# Four things the platform depends on and does not control: the generation
# service, Stripe's keys, the background queue, and the technique catalogue.
# Each answers the same three-part question — is it there, what does it say,
# and does anything need doing.
class PlatformStatus
  Check = Data.define(:key, :state, :detail) do
    def ok? = state == :ok
    def warning? = state == :warning
    def down? = state == :down
  end

  def self.call = new.call

  def call = [ generator, stripe, queue, catalogue ]

  private
    # The one call in the application that reaches the service without a key:
    # `/health` is public by the microservice's own contract.
    def generator
      body = Net::HTTP.get_response(URI.join(generator_url, "/health"))
      status = JSON.parse(body.body)["status"]

      if status == "ok"
        Check.new(key: :generator, state: :ok, detail: generator_url)
      else
        Check.new(key: :generator, state: :warning, detail: status.to_s)
      end
    rescue URI::InvalidURIError, TypeError, ArgumentError
      Check.new(key: :generator, state: :down, detail: I18n.t("admin.status.not_configured"))
    rescue StandardError => e
      Check.new(key: :generator, state: :down, detail: e.class.to_s)
    end

    def generator_url
      ENV["GENERATOR_URL"].presence ||
        Rails.application.credentials.dig(:generator, :url) ||
        raise(URI::InvalidURIError)
    end

    # Not a call to Stripe: asking it whether our keys work would cost a
    # request on every page load. Whether they are set at all is the question
    # that actually catches the mistake.
    def stripe
      missing = %w[ STRIPE_SECRET_KEY STRIPE_WEBHOOK_SECRET
                    STRIPE_PRICE_LISTING STRIPE_PRICE_ATELIER_PLUS ].reject do |key|
        ENV[key].present? || Rails.application.credentials.dig(:stripe, key.downcase.delete_prefix("stripe_").to_sym).present?
      end

      if missing.empty?
        Check.new(key: :stripe, state: :ok, detail: nil)
      else
        Check.new(key: :stripe, state: :warning, detail: missing.join(", "))
      end
    end

    # A queue that is not being worked is the failure that looks like nothing
    # at all: pages render, and generations simply never finish.
    def queue
      pending = SolidQueue::Job.where(finished_at: nil).count
      failed = SolidQueue::FailedExecution.count

      if failed.positive?
        Check.new(key: :queue, state: :warning, detail: I18n.t("admin.status.failed_jobs", count: failed))
      else
        Check.new(key: :queue, state: :ok, detail: I18n.t("admin.status.pending_jobs", count: pending))
      end
    rescue StandardError => e
      Check.new(key: :queue, state: :down, detail: e.class.to_s)
    end

    # A cold cache falls back to the bundled copy, which is correct but stale:
    # worth saying so rather than letting a renamed technique surprise someone.
    def catalogue
      cached = Rails.cache.read(PrintTechniques::CACHE_KEY).present?

      Check.new(key: :catalogue,
                state: cached ? :ok : :warning,
                detail: I18n.t("admin.status.techniques", count: PrintTechniques.keys.size))
    end
end
