# Brings what the client asked for within what can actually be printed.
#
# Two ceilings apply, in this order: the technique's, because the generator
# will not exceed it anyway, and then the shop's, because a four-screen press
# cannot print six. Silently lowering is right here — the alternative is
# refusing a form over a slider the client never saw a limit on.
class BoundedGenerationRequest
  def self.call(attributes:, printer:) = new(attributes: attributes, printer: printer).call

  def initialize(attributes:, printer:)
    @attributes = attributes
    @printer = printer
  end

  def call
    entry = PrintTechniques.find(@attributes[:technique])
    return @attributes if entry.nil?

    @attributes.merge(
      colors_requested: bounded_colors(entry),
      print_width_cm: bounded_width(entry)
    )
  end

  private
    # A technique that prints every colour at once has no ink count to send:
    # keeping one would state a limit the machine has not got.
    def bounded_colors(entry)
      return nil unless entry.limited_colors?

      asked = @attributes[:colors_requested].presence&.to_i || entry.default_colors
      ceilings = [ asked, entry.max_colors, shop_technique(entry)&.max_colors ].compact

      [ ceilings.min, 1 ].max
    end

    def bounded_width(entry)
      asked = @attributes[:print_width_cm].presence&.to_i
      return asked if asked.nil?

      [ asked, shop_technique(entry)&.effective_max_width_cm ].compact.min
    end

    def shop_technique(entry) = @printer&.technique_for(entry.key)
end
