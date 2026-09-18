require "net/http"

# Checks a Cloudflare Turnstile token against Cloudflare.
#
# This is the one place the application talks to a third party inside the
# request cycle rather than from a background job: an anti-robot check is only
# useful if it answers before the form is accepted. Every other outgoing call
# belongs in a job. See docs/SPEC.md, "Conventions".
class TurnstileVerifier
  ENDPOINT = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify").freeze
  TIMEOUT_SECONDS = 5

  Result = Data.define(:outcome, :error_codes) do
    def success? = outcome == :success

    # True when no secret key is configured, so the caller can tell "the visitor
    # passed" apart from "nobody was asked".
    def skipped? = outcome == :skipped
  end

  class << self
    def site_key = credential(:site_key, "TURNSTILE_SITE_KEY")

    def secret_key = credential(:secret_key, "TURNSTILE_SECRET_KEY")

    def configured? = secret_key.present?

    def call(token:, ip: nil) = new(token: token, ip: ip).call

    private
      def credential(name, variable)
        ENV[variable].presence || Rails.application.credentials.dig(:turnstile, name)
      end
  end

  def initialize(token:, ip: nil)
    @token = token
    @ip = ip
  end

  def call
    return skipped unless self.class.configured?
    return failure(%w[ missing-input-response ]) if @token.blank?

    parse(post)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, JSON::ParserError => e
    # Cloudflare being unreachable must not read as "this visitor is a robot",
    # but it must not silently let everyone through either: the caller decides,
    # and the failure is logged.
    Rails.logger.warn("[turnstile] verification unavailable: #{e.class}")
    failure(%w[ verification-unavailable ])
  end

  private
    def post
      Net::HTTP.start(ENDPOINT.host, ENDPOINT.port,
                      use_ssl: true,
                      open_timeout: TIMEOUT_SECONDS,
                      read_timeout: TIMEOUT_SECONDS) do |http|
        request = Net::HTTP::Post.new(ENDPOINT)
        request.set_form_data({ secret: self.class.secret_key, response: @token, remoteip: @ip }.compact)
        http.request(request)
      end
    end

    def parse(response)
      body = JSON.parse(response.body)
      body["success"] ? success : failure(Array(body["error-codes"]))
    end

    def success = Result.new(outcome: :success, error_codes: [])
    def skipped = Result.new(outcome: :skipped, error_codes: [])
    def failure(codes) = Result.new(outcome: :failure, error_codes: codes)
end
