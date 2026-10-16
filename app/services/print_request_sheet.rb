# The technical sheet that travels with a print request.
#
# The workshop gets the print file, but a file alone loses the intent: the SVG
# has dropped shades the client asked for, and the PNG says nothing about how it
# was made. So the sheet carries what the file cannot — the client's own words,
# the prompt the model actually used, the last refinement asked for, the inks
# with their codes, and the `seed` and `style` that let the same image be
# generated again months later.
#
# See docs/SPEC.md, "Fiche technique jointe à l'envoi".
class PrintRequestSheet
  Line = Data.define(:label, :value)

  def self.call(...) = new(...).call

  def initialize(print_request:)
    @print_request = print_request
    @design = print_request.read_association(:design)
  end

  def call
    (job_lines + file_lines + provenance_lines).compact
  end

  private
    def t(key, **options) = I18n.t("print_requests.sheet.#{key}", **options)

    def job_lines
      [
        line(:technique, @design.technique_label),
        # Not asked for a vector file, which the workshop scales as it likes
        # (decided on 14/10/2026).
        line(:print_width, ("#{@print_request.print_width_cm} cm" unless @design.vector?)),
        line(:placements, placements),
        line(:textile, textile),
        line(:delivery, (t("delivery_method.#{@print_request.delivery_method}") if @print_request.delivery_method)),
        line(:express, express),
        line(:sizes, sizes),
        line(:total_qty, @print_request.total_qty),
        line(:desired_on, @print_request.desired_on&.to_fs(:long))
      ]
    end

    def file_lines
      if @design.vector?
        [
          line(:inks, @design.inks_count),
          line(:palette, @design.palette.map { |ink| ink["hex"] }.join("  ")),
          line(:paths, @design.paths_count)
        ]
      else
        stats = @design.stats
        [
          line(:definition, ("#{stats['width_px']} × #{stats['height_px']} px" if stats["width_px"])),
          line(:resolution, ("#{stats['dpi']} dpi" if stats["dpi"])),
          line(:sharp_up_to, ("#{stats['net_width_cm']} cm" if stats["net_width_cm"]))
        ]
      end
    end

    # What lets the workshop — or us — reproduce the same image later.
    def provenance_lines
      [
        line(:starting_image, (t("starting_image_value") if starting_image?)),
        line(:asked_for, @design.prompt),
        line(:prompt_used, @design.prompt_used),
        line(:instruction, @design.instruction),
        # A client's own picture was drawn by nobody here: it has no style
        # (reported on 14/10/2026 — « Style : Illustration » on an upload).
        line(:style, (I18n.t("enums.design.style.#{@design.style}") unless @design.upload?)),
        line(:seed, @design.seed)
      ]
    end

    # By query: the request reaches here bare from mailers and jobs.
    def starting_image?
      ActiveStorage::Attachment.exists?(record_type: "PrintRequest", record_id: @print_request.id,
                                        name: "starting_image")
    end

    def line(key, value)
      Line.new(label: t(key), value: value) if value.present?
    end

    def placements
      return nil if @print_request.placements.blank?

      @print_request.placements.map { |p| I18n.t("enums.printer.placements.#{p}") }.join(", ")
    end

    def textile
      source = t("textile_source.#{@print_request.textile_source}")
      [ source, @print_request.textile_model, @print_request.textile_color ].compact_blank.join(" — ")
    end

    def express
      return nil unless @print_request.express?

      hours = Printer.where(id: @print_request.printer_id).pick(:express_lead_hours)
      hours ? t("express_value", count: hours) : t("express_yes")
    end

    def sizes
      @print_request.ordered_sizes.map { |size, quantity| "#{size} × #{quantity}" }.join("   ")
    end
end
