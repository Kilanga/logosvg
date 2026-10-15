module Workshop
  # The workshop's own converter (asked for on 15/10/2026): a JPEG or PNG the
  # shop already has — a customer's logo sent by email, a scan — put in the
  # format its machine prints, by the same route as a client's upload: nothing
  # redrawn, no generation counted, the service vectorising or preparing the
  # image as it would one of its own.
  #
  # The difference with a client's upload is what comes back. The shop owns the
  # picture and is the one who prints: it downloads the print file itself, SVG
  # or PNG, where a client only ever gets a watermarked preview.
  #
  # Conversions are designs of the shop's account, so the same retention
  # applies: never sent anywhere, they are purged with the other unsent designs.
  class ConversionsController < BaseController
    require_verified_email only: %i[ new create ]

    rate_limit to: 10, within: 1.minute, only: :create,
               with: -> { redirect_to new_workshop_conversion_path, alert: t("flash.rate_limited") }

    before_action :set_design, only: %i[ show destroy download original ]

    def index
      authorize Design, :conversions?

      @designs = policy_scope(Design).where(mode: "upload").with_attached_print_file
                                     .newest_first.limit(50)
    end

    def new
      @design = Design.new(defaults)
      authorize @design, :convert?
    end

    def create
      @design = Design.new(conversion_params.merge(user: Current.user, printer: current_printer,
                                                   mode: "upload", style: "illustration"))
      authorize @design, :convert?

      return refuse(t(".unknown_technique")) unless technique_keys.include?(@design.technique)

      upload = params.dig(:design, :reference_image)
      return refuse(t(".missing_image")) if upload.blank?

      image = ReferenceImage.call(upload, max_side: ReferenceImage::PRINT_SIDE_PX)
      return refuse(image.error) unless image.success?

      @design.reference_image.attach(image.attachable)

      if @design.save
        GenerateDesignJob.perform_later(@design)
        redirect_to workshop_conversion_path(@design)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      authorize @design
    end

    def download
      authorize @design, :download_print_file?

      blob = @design.print_file.blob
      send_data blob.download, type: blob.content_type, disposition: "attachment",
                               filename: "#{@design.prompt.parameterize.presence || @design.token}.#{blob.filename.extension}"
    end

    # The picture as it was sent, re-encoded on its way in, beside the result.
    def original
      authorize @design, :show?
      return head :not_found unless @design.reference_image.attached?

      send_data @design.reference_image.download, type: "image/png", disposition: "inline",
                filename: "#{@design.token}-original.png"
    end

    def destroy
      authorize @design

      @design.soft_delete!
      redirect_to workshop_conversions_path, notice: t(".deleted"), status: :see_other
    end

    private
      def set_design
        @design = policy_scope(Design).where(mode: "upload")
                                      .with_attached_print_file.with_attached_reference_image
                                      .find_by!(token: params[:token])
      end

      def refuse(message)
        flash.now[:alert] = message
        render :new, status: :unprocessable_entity
      end

      # What the shop practises, in the order of its listing. The form's
      # partials are the client's, and read these two names.
      def available_techniques
        technique_keys.map { |key| PrintTechniques.find(key) }.compact
      end

      def technique_keys = current_printer&.technique_keys || []

      def context_printer = current_printer
      helper_method :available_techniques, :context_printer

      def defaults
        technique = available_techniques.first
        {
          technique: technique&.key,
          colors_requested: (technique&.default_colors if technique&.limited_colors?),
          print_width_cm: Rails.application.config.tshirt.generation[:default_print_width_cm],
          remove_background: true
        }
      end

      # The rights are confirmed as a client confirms them: the shop says it may
      # print the picture, which is the question its own customer's logo raises.
      def conversion_params
        permitted = params.expect(design: [ :prompt, :technique, :colors_requested, :print_width_cm,
                                            :remove_background, :reference_rights_confirmed, :ai_declared ])
        permitted[:prompt] = t("workshop.conversions.default_title") if permitted[:prompt].to_s.strip.length < 3
        BoundedGenerationRequest.call(attributes: permitted, printer: current_printer)
      end
  end
end
