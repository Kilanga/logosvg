module Designer
  # The workshop's converter, inside a client's review (asked for on
  # 17/10/2026): the designer's own PNG or JPEG — the reworked picture — put in
  # the format the client's workshop prints, by the same route as a shop's
  # conversion. Nothing redrawn, no generation counted.
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

      upload = params[:image]
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

    private
      def set_review
        @review = policy_scope(Review).includes(:design).find_by!(token: params[:token])
      end

      # The review's own design says what the workshop prints: its technique,
      # inks and width, and whether it came out of a model.
      def build_conversion
        source = @review.design
        Design.new(
          user: Current.user, printer_id: source.printer_id, conversion_review: @review,
          mode: "upload", style: "illustration",
          prompt: t(".title", reference: @review.token.first(8).upcase),
          technique: source.technique, colors_requested: source.colors_requested,
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
