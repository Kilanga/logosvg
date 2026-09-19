# Checks an SVG before it is ever stored or shown.
#
# An SVG is a document, not a picture: it can carry scripts, fetch remote
# resources and expand entities until the server runs out of memory. Every SVG
# is inspected — the ones the service generates as much as the ones a designer
# uploads — because "we made it ourselves" is how the first one gets through.
#
# See docs/SPEC.md, "Fichiers".
class SvgInspector
  MAX_BYTES = 5.megabytes

  FORBIDDEN_ELEMENTS = %w[ script foreignObject iframe embed object use image ].freeze

  # Anything that reaches outside the document: a remote stylesheet, a tracking
  # pixel, a javascript: URL.
  EXTERNAL_URL = /\A\s*(?:https?:|\/\/|data:(?!image\/(?:png|jpeg);base64,)|javascript:|file:)/i

  # The same, inside a stylesheet, where a URL is not an attribute value but a
  # `url(...)` or an `@import`. Checked because the renderer that rasterises the
  # file — librsvg, through libvips — honours stylesheets.
  STYLE_EXTERNAL_URL = /@import|url\(\s*["']?\s*(?:https?:|\/\/|file:)/i

  Result = Data.define(:valid, :reason, :inks, :fills) do
    def valid? = valid
  end

  def self.call(source) = new(source).call

  def initialize(source)
    @source = source
  end

  def call
    return refuse(:too_large) if @source.to_s.bytesize > MAX_BYTES
    return refuse(:empty) if @source.blank?

    document = parse
    return refuse(:not_svg) if document.nil? || document.root&.name != "svg"

    reason = forbidden_content(document)
    return refuse(reason) if reason

    fills = distinct_fills(document)
    Result.new(valid: true, reason: nil, inks: fills.size, fills: fills)
  end

  private
    # NOENT is never enabled, and entities are refused outright: expanding them
    # is the billion-laughs attack.
    def parse
      Nokogiri::XML(@source) do |config|
        config.strict.nonet.noblanks
      end
    rescue Nokogiri::XML::SyntaxError
      nil
    end

    def forbidden_content(document)
      return :entity if @source.include?("<!ENTITY") || @source.include?("<!DOCTYPE")

      document.traverse do |node|
        next unless node.element?

        return :forbidden_element if FORBIDDEN_ELEMENTS.include?(node.name)
        return :external_reference if node.name == "style" && node.text.match?(STYLE_EXTERNAL_URL)

        node.attribute_nodes.each do |attribute|
          return :event_handler if attribute.name.downcase.start_with?("on")
          return :external_reference if attribute.value.to_s.match?(EXTERNAL_URL)
          return :external_reference if attribute.name == "style" &&
                                        attribute.value.to_s.match?(STYLE_EXTERNAL_URL)
        end
      end

      nil
    end

    # One distinct fill is one ink, which is one screen. Counted here rather
    # than trusted from the service, because a designer's upload has no service
    # behind it.
    def distinct_fills(document)
      document.css("[fill]")
              .map { |node| node["fill"].to_s.strip.downcase }
              .reject { |fill| fill.empty? || fill == "none" }
              .uniq
              .sort
    end

    def refuse(reason) = Result.new(valid: false, reason: reason, inks: nil, fills: [])
end
