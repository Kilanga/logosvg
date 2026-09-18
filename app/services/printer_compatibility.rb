# Can this shop print this design?
#
# Three questions, in the order that decides fastest, each carrying the sentence
# the visitor will read. Written now, before any Design exists: the directory
# and the shop page need it at step 2, and step 3 plugs a real design into the
# same call rather than rewriting the rule.
#
# See docs/SPEC.md, "Compatibilité atelier".
class PrinterCompatibility
  # `reason` is the symbol tests assert on; `message` is the sentence the screen
  # shows. Keeping both means a wording change never breaks a test, and a rule
  # change always does.
  Result = Data.define(:compatible, :reason, :message) do
    def compatible? = compatible
  end

  COMPATIBLE = Result.new(compatible: true, reason: nil, message: nil)

  def self.call(printer:, technique:, inks_count: nil, print_width_cm: nil)
    new(printer: printer, technique: technique,
        inks_count: inks_count, print_width_cm: print_width_cm).call
  end

  # Judges a whole list in one pass. The caller is expected to have loaded the
  # techniques already — the directory does, and an N+1 here would be one query
  # per shop on a page built to show many.
  def self.for_each(printers, technique:, inks_count: nil, print_width_cm: nil)
    printers.index_with do |printer|
      call(printer: printer, technique: technique,
           inks_count: inks_count, print_width_cm: print_width_cm)
    end
  end

  def initialize(printer:, technique:, inks_count: nil, print_width_cm: nil)
    @printer = printer
    @technique = technique.to_s
    @inks_count = inks_count
    @print_width_cm = print_width_cm
  end

  def call
    row = @printer.technique_for(@technique)
    return refuse(:technique_not_practised, technique: technique_label) if row.nil?

    # An ink ceiling only means something where inks are counted one by one.
    unless row.prints_inks?(@inks_count)
      # The ceiling carries its own plural agreement, so it is translated first
      # and interpolated: I18n only ever agrees on `count`.
      return refuse(:too_many_inks,
                    ceiling: I18n.t("printers.ink_ceiling", count: row.max_colors),
                    count: @inks_count)
    end

    unless row.prints_width?(@print_width_cm)
      return refuse(:too_wide, max: row.effective_max_width_cm)
    end

    COMPATIBLE
  end

  private
    def technique_label = PrintTechniques.label_for(@technique)

    def refuse(reason, **details)
      Result.new(
        compatible: false,
        reason: reason,
        message: I18n.t("printers.compatibility.#{reason}", **details)
      )
    end
end
