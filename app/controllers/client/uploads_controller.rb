module Client
  # A client who already has a finished picture — drawn elsewhere, by another
  # AI or by hand — and only wants it in the format the workshop's machine
  # prints. Decided on 08/10/2026.
  #
  # Nothing is redrawn: the generation service vectorises or prepares the image
  # as it would one of its own, without the model. So it costs no generation,
  # neither the client's daily allowance nor the workshop's monthly one, and
  # offers no reprise — a designer is still there for one.
  #
  # Inherits the shop in context, the techniques it offers and the robot check
  # from the creation form, which it sits beside.
  class UploadsController < DesignsController
    def new
      @design = Design.new(defaults.merge(mode: "upload"))
      authorize @design
    end

    def create
      @design = Design.new(upload_params.merge(user: Current.user, printer: context_printer,
                                               mode: "upload", style: "illustration"))
      authorize @design

      # The picture is the whole request: without it, there is nothing to send.
      upload = params.dig(:design, :reference_image)
      if upload.blank?
        flash.now[:alert] = t(".missing_image")
        return render :new, status: :unprocessable_entity
      end

      # Re-encoded like any image a client sends — no EXIF, no GPS — but kept at
      # print definition: it is the file, not a hint.
      image = ReferenceImage.call(upload, max_side: ReferenceImage::PRINT_SIDE_PX)
      unless image.success?
        flash.now[:alert] = image.error
        return render :new, status: :unprocessable_entity
      end
      @design.reference_image.attach(image.attachable)

      unless robot_check_passed?
        flash.now[:alert] = t("flash.turnstile_failed")
        return render :new, status: :unprocessable_entity
      end

      if @design.save
        GenerateDesignJob.perform_later(@design)
        redirect_to design_path(@design)
      else
        render :new, status: :unprocessable_entity
      end
    end

    private
      def upload_params
        permitted = params.expect(design: [ :prompt, :technique, :colors_requested, :print_width_cm,
                                            :remove_background, :reference_rights_confirmed, :ai_declared ])
        permitted[:prompt] = t("client.uploads.default_title") if permitted[:prompt].to_s.strip.length < 3
        BoundedGenerationRequest.call(attributes: permitted, printer: context_printer)
      end
  end
end
