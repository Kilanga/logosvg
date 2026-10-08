# Turns a designer's accepted delivery into a design the client can send to a
# workshop, like any other.
#
# Until now the reworked file stayed on the review page: the client could look
# at it, but the print request still sent the AI's original. The latest
# version becomes a new design of the same lineage — mode "reviewed" — ready,
# with the file as its print file. It is never taken further by the AI: a
# person has finished it.
#
# Once per review: the unique index on source_review_id makes a second call
# return the design already made.
class CreateReviewedDesign
  def self.call(review:) = new(review).call

  def initialize(review)
    @review = review
  end

  def call
    existing = Design.find_by(source_review_id: @review.id)
    return existing if existing

    version = @review.versions.with_attached_file.last
    return nil unless version&.file&.attached?

    parent = Design.with_attached_source_png.find(@review.design_id)
    design = build(parent, version)

    Design.transaction do
      design.save!
      copy(version.file, to: design.print_file)
      copy(parent.source_png, to: design.source_png) if parent.source_png.attached?
    end
    design
  rescue ActiveRecord::RecordNotUnique
    Design.find_by!(source_review_id: @review.id)
  end

  private
    def build(parent, version)
      checks = version.checks || {}

      Design.new(
        user_id: parent.user_id, printer_id: parent.printer_id,
        parent_id: parent.id, root_id: parent.lineage_root_id,
        source_review_id: @review.id, mode: "reviewed",
        prompt: parent.prompt, style: parent.style, technique: parent.technique,
        colors_requested: parent.colors_requested, print_width_cm: parent.print_width_cm,
        remove_background: parent.remove_background, subject: parent.subject,
        ai_declared: parent.ai_declared,
        prompt_used: parent.prompt_used, seed: parent.seed,
        print_format: parent.vector? ? "svg" : "png",
        inks_count: version.inks_count,
        palette: Array(checks["fills"]).map { |hex| { "hex" => hex } },
        stats: raster_stats(checks),
        warnings: Array(checks["warnings"]),
        # Not to be reworked by the AI: no reprise is offered on it.
        refinements_left: nil,
        status: "ready"
      )
    end

    def raster_stats(checks)
      checks.slice("width_px", "height_px", "dpi")
    end

    # A copy, not the same blob: deleting the review must not take the
    # client's design with it.
    def copy(source, to:)
      to.attach(io: StringIO.new(source.download), filename: source.filename.to_s,
                content_type: source.content_type)
    end
end
