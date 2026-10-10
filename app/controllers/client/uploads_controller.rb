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
      prefill_from_source if source_design
    end

    def create
      @design = Design.new(upload_params.merge(user: Current.user, printer: context_printer,
                                               mode: "upload", style: "illustration"))
      authorize @design

      if source_design
        # The same picture, tried with another technique: the image already
        # sent, re-encoded on its way in, and the rights already confirmed for
        # it. Copied, not shared, so that each design owns its file.
        attach_source_image
      else
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
      end

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
      # The design whose picture is being tried again with another technique,
      # named by `depuis`. Only one of the client's own, done, and kept as sent.
      def source_design
        return @source_design if defined?(@source_design)

        token = params[:depuis].presence
        @source_design = token && policy_scope(Design).with_attached_reference_image.find_by!(token: token)
        authorize @source_design, :reconvert? if @source_design
        @source_design
      end

      # What the client said the first time stays said: the name, the
      # background, the AI declaration. Only the technique — and what follows
      # from it — is asked again.
      def prefill_from_source
        @design.assign_attributes(prompt: source_design.prompt, remove_background: source_design.remove_background,
                                  ai_declared: source_design.ai_declared,
                                  print_width_cm: source_design.print_width_cm)

        # Offered first: another of the shop's techniques, since that is the question.
        other = available_techniques.find { |entry| entry.key != source_design.technique }
        return if other.nil?

        @design.assign_attributes(technique: other.key,
                                  colors_requested: (other.default_colors if other.limited_colors?))
      end

      def attach_source_image
        @design.reference_rights_confirmed = true
        @design.ai_declared = source_design.ai_declared
        @design.reference_image.attach(io: StringIO.new(source_design.reference_image.download),
                                       filename: source_design.reference_image.filename.to_s,
                                       content_type: source_design.reference_image.content_type)
      end

      def upload_params
        permitted = params.expect(design: [ :prompt, :technique, :colors_requested, :print_width_cm,
                                            :remove_background, :reference_rights_confirmed, :ai_declared ])
        permitted[:prompt] = t("client.uploads.default_title") if permitted[:prompt].to_s.strip.length < 3
        BoundedGenerationRequest.call(attributes: permitted, printer: context_printer)
      end
  end
end
