module Client
  # Creating a design, watching it appear, and taking it further.
  #
  # The technique is the first field, because it shapes the prompt and not only
  # the output file — see docs/SPEC.md, "Techniques d'impression".
  class DesignsController < BaseController
    before_action :set_design, only: %i[ show image original_image garment_image reference_image variants refine choose destroy ]
    # A client creates through their workshop, and only once it has them —
    # see docs/SPEC.md, "Rattachement d'un client à un atelier".
    before_action :require_workshop, only: %i[ new create ]

    rate_limit to: 10, within: 1.minute, only: %i[ create variants refine ],
               with: -> { redirect_to new_design_path, alert: t("flash.rate_limited") }

    # The client's own designs, one card per lineage. A variant is not a design
    # of its own in this list — it is another take on the same idea, and showing
    # six near-identical cards would bury the six distinct ones.
    def index
      authorize Design

      # The proposals of a creation not yet chosen are one idea, not three:
      # one card, which leads to the choice.
      @lineages = policy_scope(Design).roots.newest_first
                                      .includes(:printer, children: :print_file_attachment)
                                      .with_attached_print_file
                                      .to_a.uniq { |design| design.batch_token || design.token }
    end

    def new
      @design = Design.new(defaults)
      authorize @design
    end

    def create
      @design = Design.new(design_params.merge(user: Current.user, printer: context_printer))
      authorize @design

      # The client's image, when there is one, is re-encoded before anything
      # else: what is stored and sent is never the uploaded file itself.
      if (upload = params.dig(:design, :reference_image)).present?
        image = ReferenceImage.call(upload)
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

      # The workshop's monthly generations, when its plan has a ceiling.
      unless PrinterGenerationQuota.for(context_printer).allows?
        flash.now[:alert] = t("client.designs.workshop_quota_reached", printer: context_printer.name)
        return render :new, status: :unprocessable_entity
      end

      # The allowance is taken before the job is queued, not after: two
      # submissions in the same instant must not both get through.
      unless GenerationQuota.for(Current.user).consume!
        flash.now[:alert] = t(".quota_exceeded", count: GenerationQuota.per_day)
        return render :new, status: :unprocessable_entity
      end

      if @design.save
        # The other proposals of the click, waiting for the same job.
        SpawnProposals.call(@design)
        GenerateDesignJob.perform_later(@design)
        PrinterGenerationQuota.for(context_printer).notify_if_reached!
        redirect_to design_path(@design)
      else
        GenerationQuota.for(Current.user).refund!
        render :new, status: :unprocessable_entity
      end
    end

    def show
      authorize @design
      @proposals = proposals_on_offer
      @compatible_printers = compatible_printers
    end

    # The client keeps this proposal; the others of its click are set aside.
    def choose
      authorize @design

      ChooseProposal.call(@design)
      case params[:suite]
      when "atelier" then redirect_to new_design_print_request_path(@design)
      when "graphiste" then redirect_to new_design_review_path(@design)
      else redirect_to design_path(@design), notice: t(".chosen")
      end
    end

    # The only rendering a client ever receives: a watermarked raster of the
    # print file, never the print file itself.
    def image
      authorize @design

      preview = DesignPreview.call(@design)
      return head :not_found if preview.nil?

      send_data preview, type: "image/png", disposition: "attachment",
                filename: "#{@design.token}.png"
    end

    # For comparison only — the "rendu final / image d'origine" selector. Also
    # watermarked, and never the deciding rendering: see DesignPreview.
    def original_image
      authorize @design, :image?

      preview = DesignPreview.call(@design, variant: :source_png)
      return head :not_found if preview.nil?

      send_data preview, type: "image/png", disposition: "attachment",
                filename: "#{@design.token}-original.png"
    end

    # The print file kept transparent, for the garment silhouette only: on a
    # dark fabric the unprinted areas must show the fabric, not a white square.
    # Watermarked like every other rendering, and shown inline, not downloaded.
    def garment_image
      authorize @design, :image?

      preview = DesignPreview.call(@design, variant: :garment)
      return head :not_found if preview.nil?

      send_data preview, type: "image/png", disposition: "inline",
                filename: "#{@design.token}-textile.png"
    end

    # The client's own image, back to the client only. Already re-encoded on
    # the way in: no EXIF, no GPS.
    def reference_image
      authorize @design, :image?
      return head :not_found unless @design.reference_image.attached?

      send_data @design.reference_image.download, type: "image/png", disposition: "inline",
                filename: "#{@design.token}-image-de-depart.png"
    end

    def variants
      authorize @design
      take_it_further { GeneratorClient.new.variants(@design.generator_job_id, user_id: Current.user.id) }
    end

    def refine
      authorize @design
      @instruction = params[:instruction].to_s.strip
      take_it_further do
        GeneratorClient.new.refine(@design.generator_job_id, instruction: @instruction, user_id: Current.user.id)
      end
    end

    # Soft-deleted, never destroyed: a print request already sent keeps its own
    # copies of the files, and the workshop's job must not lose its origin.
    def destroy
      authorize @design

      @design.soft_delete!
      redirect_to client_designs_path, notice: t(".deleted")
    end

    private
      def set_design
        @design = policy_scope(Design).with_attached_print_file.with_attached_source_png
                                      .with_attached_reference_image
                                      .includes(printer: :subscription)
                                      .find_by!(token: params[:token])
      end

      # Both a variant and a refinement produce children of the same lineage,
      # fail the same way, and cost the same allowance — so they share a path.
      #
      # The budget is checked here first, on the application's own count: the
      # service's resets whenever its machine is switched off. And a design the
      # machine has forgotten is put back on it once, then asked again.
      def take_it_further
        # A retouche is the client's own words too: the platform's list reads
        # them here, before anything is spent or sent.
        if @instruction.present? && (term = BlockedTerm.matching(@instruction))
          BlockedTerm.record_hit!(term)
          return redirect_to design_path(@design), alert: t("client.designs.take_it_further.blocked")
        end

        # Every reprise counts against the shop the design was made for. Once
        # the client has left that shop — or it has let them go — it no longer
        # pays for their reprises: a new design, with the new shop, does.
        unless reprise_allowed?
          return redirect_to design_path(@design), alert: t("client.designs.take_it_further.other_workshop")
        end

        if @design.refinements_remaining.zero?
          return redirect_to design_path(@design), alert: t(".budget_exhausted")
        end

        workshop_quota = PrinterGenerationQuota.for(@design.printer)
        unless workshop_quota.allows?
          return redirect_to design_path(@design),
                             alert: t("client.designs.workshop_quota_reached", printer: @design.printer.name)
        end

        unless GenerationQuota.for(Current.user).consume!
          return redirect_to design_path(@design),
                             alert: t("client.designs.create.quota_exceeded", count: GenerationQuota.per_day)
        end

        children = CreateDesignChildren.call(parent: @design, instruction: @instruction) do
          yield
        rescue GeneratorClient::NotFound
          ReviveDesign.call(@design)
          yield
        end
        # Retouched or varied straight from the choice screen: the proposal
        # it started from is the one kept.
        ChooseProposal.call(@design) if @design.awaiting_choice?
        workshop_quota.notify_if_reached!
        redirect_to design_path(children.first)
      rescue ReviveDesign::Unrecoverable
        GenerationQuota.for(Current.user).refund!
        redirect_to design_path(@design), alert: t("client.designs.take_it_further.too_old")
      rescue GeneratorClient::BudgetExhausted
        GenerationQuota.for(Current.user).refund!
        redirect_to design_path(@design), alert: t(".budget_exhausted")
      rescue GeneratorClient::Rejected => e
        GenerationQuota.for(Current.user).refund!
        redirect_to design_path(@design), alert: e.detail
      rescue GeneratorClient::Error
        GenerationQuota.for(Current.user).refund!
        redirect_to design_path(@design), alert: t("designs.errors.unavailable")
      end

      # The client's workshop, from the account rather than from the visit:
      # since 09/10/2026 a client belongs to one shop, which agreed to it.
      # Nil while the shop has not, or once it is no longer listed.
      def context_printer
        return @context_printer if defined?(@context_printer)

        # Avec ses techniques et son abonnement : `technique_keys` lit les
        # premières, `listed?` le second, et les deux sont lus dès le formulaire.
        @context_printer = (Printer.listed.includes(:techniques, :subscription)
                                   .find_by(id: Current.user.active_workshop_id) if Current.user&.active_workshop_id)
      end

      # Without a listed shop there is nothing to create for: the dashboard says
      # why — a request still waiting, or a shop to find.
      def require_workshop
        return unless Current.user&.client?
        return if context_printer

        redirect_to client_dashboard_path, alert: t("client.designs.workshop_required")
      end

      def reprise_allowed?
        Current.user.attached_to_workshop? &&
          (@design.printer_id.nil? || @design.printer_id == Current.user.active_workshop_id)
      end

      # A shop in context narrows the choice to what it actually does; without
      # one, the whole catalogue is offered.
      def available_techniques
        return PrintTechniques.all if context_printer.nil?

        context_printer.technique_keys.map { |key| PrintTechniques.fetch(key) }
      end
      helper_method :available_techniques, :context_printer

      def defaults
        technique = available_techniques.first
        {
          technique: technique&.key,
          colors_requested: (technique&.default_colors if technique&.limited_colors?),
          print_width_cm: Rails.application.config.tshirt.generation[:default_print_width_cm]
        }
      end

      def design_params
        permitted = params.expect(design: [ :prompt, :style, :technique, :colors_requested,
                                            :print_width_cm, :remove_background,
                                            :reference_rights_confirmed ])
        BoundedGenerationRequest.call(attributes: permitted, printer: context_printer)
      end

      def robot_check_passed?
        TurnstileVerifier.call(token: params["cf-turnstile-response"], ip: request.remote_ip)
                         .then { |result| result.success? || result.skipped? }
      end

      # Every proposal of the click, while the client has not kept one. Loaded
      # with what the panel shows: each is rendered with the same partial.
      def proposals_on_offer
        return [] unless @design.awaiting_choice?

        @design.proposals.with_attached_print_file.with_attached_source_png
               .with_attached_reference_image.to_a
      end

      # Who could print this, for the panel under the preview. Techniques are
      # loaded in one go: this asks the question of every listed shop.
      def compatible_printers
        return [] unless @design.ready? && !@design.awaiting_choice?

        Printer.listed.includes(:techniques).by_prominence.select do |printer|
          @design.compatibility_with(printer).compatible?
        end
      end
  end
end
