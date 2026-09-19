require "net/http"

# The only thing in the application that talks to the generation microservice.
#
# Called from background jobs, never from a request: the service runs on another
# machine behind a tunnel, and a page must not wait on it. See docs/SPEC.md,
# "Intégration du microservice".
class GeneratorClient
  TIMEOUT_SECONDS = 20

  # Every failure carries the service's own JSON body: the two 429s are told
  # apart by it, and a 422 carries the sentence to show the client.
  class Error < StandardError
    attr_reader :body, :status

    def initialize(message = nil, body: {}, status: nil)
      @body = body || {}
      @status = status
      super(message || @body["detail"] || "the generator refused the request")
    end

    def detail = body["detail"]
  end

  # A configuration fault, never the client's: the key is wrong or missing.
  Unauthorized = Class.new(Error)
  # The job belongs to someone else, or has expired off the machine.
  NotFound = Class.new(Error)
  # A refinement asked for before the previous version is ready.
  NotReady = Class.new(Error)
  # A blocked term or an unusable prompt. The service's message is shown as is.
  Rejected = Class.new(Error)
  # The queue is full, the service is down, the network is not there.
  Unavailable = Class.new(Error)

  # The hourly generation limit. The client simply tries again later.
  class RateLimited < Error
    def retry_after = body["retry_after"]
  end

  # The design's refinement budget, spent. Definitive, and what opens the
  # designer review path — a different outcome entirely from RateLimited.
  BudgetExhausted = Class.new(Error)

  def self.techniques = new.techniques

  def initialize(base_url: nil, api_key: nil)
    @base_url = base_url || ENV["GENERATOR_URL"].presence ||
                Rails.application.credentials.dig(:generator, :url)
    @api_key = api_key || ENV["GENERATOR_API_KEY"].presence ||
               Rails.application.credentials.dig(:generator, :api_key)
  end

  # The catalogue of printing techniques. Authoritative: the application stores
  # a cached copy for its forms, never a second definition.
  def techniques
    get("/techniques").fetch("techniques")
  end

  # Starts a generation. `colors` is omitted for techniques that do not count
  # inks — sending one would state a limit the machine has not got.
  def generate(design)
    post("/generate", {
      prompt: design.prompt,
      style: design.style,
      technique: design.technique,
      colors: design.colors_requested,
      print_width_cm: design.print_width_cm,
      remove_background: design.remove_background,
      user_id: pseudonym(design.user),
      seed: design.seed
    }.compact)
  end

  def refine(job_id, instruction:, user:)
    post("/jobs/#{job_id}/refine", { instruction: instruction, user_id: pseudonym(user) })
  end

  def variants(job_id, user:, count: 3)
    post("/jobs/#{job_id}/variants", { user_id: pseudonym(user), count: count })
  end

  def job(job_id, user:)
    get("/jobs/#{job_id}", user_id: pseudonym(user))
  end

  # The generated file, as bytes. `name` comes from `result.print_file`: the
  # application never presumes an extension.
  def download(job_id, name, user:)
    fetch_body("/jobs/#{job_id}/#{name}", user_id: pseudonym(user))
  end

  private
    # The service never learns who the client is: it receives an HMAC of the
    # account id, truncated to what its own pattern accepts. See docs/SPEC.md,
    # "RGPD".
    def pseudonym(user)
      key = ENV["GENERATOR_USER_KEY"].presence ||
            Rails.application.credentials.dig(:generator, :user_key)
      raise Unavailable, "GENERATOR_USER_KEY is not configured" if key.blank?

      OpenSSL::HMAC.hexdigest("SHA256", key, user.id.to_s).first(32)
    end

    def get(path, **query) = JSON.parse(fetch_body(path, **query))

    def post(path, payload)
      request = Net::HTTP::Post.new(uri_for(path))
      request["Content-Type"] = "application/json"
      request.body = payload.to_json

      JSON.parse(perform(request).body)
    rescue JSON::ParserError => e
      raise Unavailable.new("unreadable answer from the generator: #{e.message}")
    end

    def fetch_body(path, **query)
      perform(Net::HTTP::Get.new(uri_for(path, **query))).body
    end

    def uri_for(path, **query)
      raise Unavailable, "GENERATOR_URL is not configured" if @base_url.blank?

      uri = URI.join(@base_url, path)
      uri.query = URI.encode_www_form(query) if query.any?
      uri
    end

    def perform(request)
      request["X-API-Key"] = @api_key
      uri = request.uri

      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: TIMEOUT_SECONDS,
                                 read_timeout: TIMEOUT_SECONDS) { |http| http.request(request) }

      interpret(response)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, EOFError => e
      raise Unavailable.new("#{e.class}: #{e.message}")
    end

    def interpret(response)
      return response if response.is_a?(Net::HTTPSuccess)

      body = parse_error(response)

      case response
      when Net::HTTPUnauthorized then raise Unauthorized.new(body: body, status: 401)
      when Net::HTTPNotFound then raise NotFound.new(body: body, status: 404)
      when Net::HTTPConflict then raise NotReady.new(body: body, status: 409)
      when Net::HTTPUnprocessableEntity then raise Rejected.new(body: body, status: 422)
      when Net::HTTPTooManyRequests then raise rate_limit_error(response, body)
      else raise Unavailable.new("the generator answered #{response.code}", body: body, status: response.code.to_i)
      end
    end

    # The two 429s mean opposite things: one is "come back later", the other is
    # "this design has had its three goes". Only the body tells them apart.
    def rate_limit_error(response, body)
      if body["reason"] == "refine_budget"
        BudgetExhausted.new(body: body, status: 429)
      else
        RateLimited.new(body: body.merge("retry_after" => response["Retry-After"].to_i), status: 429)
      end
    end

    # An error body that is not JSON is still an error: the status carries the
    # meaning, and an empty hash keeps every caller from having to check.
    def parse_error(response)
      JSON.parse(response.body.presence || "{}")
    rescue JSON::ParserError
      {}
    end
end
