module Workshop
  # The reviews ordered on designs made for this shop (decided on 09/10/2026):
  # what a designer is doing to a visual that will come to its press. Read
  # only — the work is between the client and the designer; the shop follows
  # it here and in copy of the emails.
  class ReviewsController < BaseController
    skip_after_action :verify_policy_scoped

    before_action :set_printer

    def index
      authorize @printer, :update?

      # Every active designer, for the recommendation: one this shop trusts
      # may not be taking work today, and can still be named.
      @designers = DesignerProfile.listed.by_reputation.to_a

      @reviews = Review.joins(:design).where(designs: { printer_id: @printer.id })
                       .where.not(status: "awaiting_payment")
                       .includes(:client, :review_level, :designer_profile, :design)
                       .order(created_at: :desc).limit(200).to_a
    end

    # One designer, or none (decided on 09/10/2026). Shown first, with « Recommandé
    # par votre atelier », on the review form of this shop's clients.
    def recommend
      authorize @printer, :update?

      id = params[:designer_profile_id].presence
      designer = id && DesignerProfile.listed.find_by(id: id)
      @printer.update_columns(recommended_designer_profile_id: designer&.id, updated_at: Time.current)
      redirect_to workshop_reviews_path,
                  notice: designer ? t(".done", name: designer.display_name) : t(".cleared")
    end

    private
      def set_printer
        @printer = current_printer
        redirect_to edit_workshop_profile_path, alert: t("workshop.links.show.no_listing") unless @printer&.persisted?
      end
  end
end
