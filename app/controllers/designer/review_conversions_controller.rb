module Designer
  # The workshop's converter, inside a client's review (asked for on
  # 17/10/2026): a picture put in a file format by the same route as a shop's
  # conversion. Nothing redrawn, no generation counted.
  #
  # Two pictures, two directions. The designer's own PNG or JPEG — the
  # reworked picture — goes to the format the client's workshop prints, to be
  # delivered. The client's picture (the design under review, or the photo it
  # was drawn from) goes the other way too: to an editable SVG of up to six
  # inks, or a high-definition PNG, whichever the designer works in.
  #
  # Only here, never as a tool of its own: the technique, the inks and the
  # width are the review's, and the result is meant to be delivered as a
  # version of it. The design it makes is the designer's, names the review,
  # and is purged with the other designs never sent anywhere.
  class ReviewConversionsController < BaseController
    rate_limit to: 10, within: 1.minute, only: :create,
               with: -> { redirect_to designer_review_path(params[:token]), alert: t("flash.rate_limited") }

    before_action :set_review

    def create
      authorize @review, :convert?

      upload = picture
      return back_with(t(".missing_image")) if upload.blank?

      image = ReferenceImage.call(upload, max_side: ReferenceImage::PRINT_SIDE_PX)
      return back_with(image.error) unless image.success?

      design = build_conversion
      design.reference_image.attach(image.attachable)

      if design.save
        GenerateDesignJob.perform_later(design)
        redirect_to designer_review_path(@review, anchor: "conversions"), notice: t(".started")
      else
        back_with(design.errors.full_messages.to_sentence)
      end
    end

    # The converted print file itself, for the designer to deliver as a version.
    def download
      authorize @review, :download_files?

      design = @review.conversions.where(user: Current.user).with_attached_print_file
                      .find_by!(token: params[:design_token])
      return head :not_found unless design.ready? && design.print_file.attached?

      blob = design.print_file.blob
      send_data blob.download, type: blob.content_type, disposition: "attachment",
                               filename: "#{@review.token.first(8).downcase}-converti.#{blob.filename.extension}"
    end

    # The formats a designer can ask for besides the workshop's own: a vector
    # file with every ink it can hold, and a raster at print definition.
    TARGETS = { "svg" => { technique: "screen_printing", colors_requested: 6 },
                "png" => { technique: "dtg", colors_requested: nil } }.freeze

    # The client's pictures a designer may convert: the design they sent for
    # review, and the photo it was drawn from, when there is one.
    def self.client_pictures(design)
      drawing = design.source_png.attached? ? design.source_png : design.print_file
      drawing = nil unless drawing.attached? && ReferenceImage::ACCEPTED.include?(drawing.content_type)
      start = design.starting_image_holder&.reference_image
      { "client_design" => drawing, "client_start" => start }.compact
    end

    private
      def set_review
        @review = policy_scope(Review).includes(design: { source_png_attachment: :blob, print_file_attachment: :blob })
                                      .find_by!(token: params[:token])
      end

      # The review's own design says what the workshop prints: its technique,
      # inks and width, and whether it came out of a model.
      def picture
        return params[:image] unless params[:source].to_s.start_with?("client_")

        attachment = self.class.client_pictures(@review.design)[params[:source]]
        StringIO.new(attachment.download) if attachment
      end

      def target = TARGETS.fetch(params[:target].to_s) { {} }

      def build_conversion
        source = @review.design
        Design.new(
          user: Current.user, printer_id: source.printer_id, conversion_review: @review,
          mode: "upload", style: "illustration",
          prompt: t(".title", reference: @review.token.first(8).upcase),
          technique: target.fetch(:technique, source.technique),
          colors_requested: target.fetch(:colors_requested, source.colors_requested),
          print_width_cm: source.print_width_cm,
          remove_background: params[:remove_background] == "1",
          ai_declared: source.ai_generated?,
          reference_rights_confirmed: true
        )
      end

      def back_with(message)
        redirect_to designer_review_path(@review, anchor: "conversions"), alert: message
      end
  end
end
