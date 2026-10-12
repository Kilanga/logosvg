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
    #
    # Short timeouts: this runs while the administrator waits for the page, and
    # Net::HTTP's default would hold it a full minute when the GPU machine is
    # asleep. Each failure says, in words, which of the three usual causes it is
    # — a name the server cannot resolve, a machine that refuses, a machine that
    # does not answer — with the address it tried.
    def generator
      uri = URI.join(generator_url, "/health")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: HEALTH_TIMEOUT, read_timeout: HEALTH_TIMEOUT) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end
      status = JSON.parse(response.body)["status"]

      if status == "ok"
        Check.new(key: :generator, state: :ok, detail: generator_url)
      else
        Check.new(key: :generator, state: :warning, detail: status.to_s)
      end
    rescue URI::InvalidURIError, TypeError, ArgumentError
      Check.new(key: :generator, state: :down, detail: I18n.t("admin.status.not_configured"))
    rescue StandardError => e
      Check.new(key: :generator, state: :down, detail: generator_failure(e))
    end

    HEALTH_TIMEOUT = 5

    def generator_failure(error)
      reason = case error
      when SocketError then :unresolved            # Socket::ResolutionError included
      when Errno::ECONNREFUSED then :refused
      when Net::OpenTimeout, Net::ReadTimeout, Errno::EHOSTUNREACH, Errno::ENETUNREACH then :timeout
      when JSON::ParserError then :unreadable
      end
      host = URI.parse(generator_url).host

      if reason
        I18n.t("admin.status.generator.#{reason}", host: host)
      else
        I18n.t("admin.status.generator.other", host: host, error: "#{error.class}: #{error.message}")
      end
    rescue StandardError
      error.class.to_s
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
                    STRIPE_PRICE_LISTING STRIPE_PRICE_ATELIER_PLUS
                    STRIPE_CONNECT_WEBHOOK_SECRET ].reject do |key|
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
