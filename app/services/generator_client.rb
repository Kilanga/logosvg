require "net/http"

# The only thing in the application that talks to the generation microservice.
#
# Called from background jobs, never from a request: the service runs on another
# machine behind a tunnel, and a page must not wait on it. See docs/SPEC.md,
# "Intégration du microservice".
class GeneratorClient
  TIMEOUT_SECONDS = 20

  Error = Class.new(StandardError)
  # Wrong or missing API key: a configuration fault, never the client's.
  Unauthorized = Class.new(Error)
  Unavailable = Class.new(Error)

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

  private
    def get(path)
      raise Unavailable, "GENERATOR_URL is not configured" if @base_url.blank?

      uri = URI.join(@base_url, path)
      request = Net::HTTP::Get.new(uri)
      request["X-API-Key"] = @api_key

      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: TIMEOUT_SECONDS,
                                 read_timeout: TIMEOUT_SECONDS) { |http| http.request(request) }

      interpret(response)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, EOFError => e
      raise Unavailable, "#{e.class}: #{e.message}"
    end

    def interpret(response)
      case response
      when Net::HTTPSuccess then JSON.parse(response.body)
      when Net::HTTPUnauthorized then raise Unauthorized, "the generator refused the API key"
      else raise Unavailable, "the generator answered #{response.code}"
      end
    rescue JSON::ParserError => e
      raise Unavailable, "unreadable answer from the generator: #{e.message}"
    end
end
