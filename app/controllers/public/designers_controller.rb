module Public
  # The public list of designers, and each one's page.
  class DesignersController < BaseController
    def index
      @designers = policy_scope(DesignerProfile)
                     .then { |scope| filtered(scope) }
                     .by_reputation
                     .includes(:review_levels)
                     .with_attached_avatar
    end

    def show
      @designer = DesignerProfile.includes(:review_levels)
                                 .with_attached_avatar.with_attached_portfolio
                                 .find(params[:id])
      authorize @designer
    end

    private
      # Specialty and level, the two things a client actually chooses on. The
      # "available now" filter is the one that matters most: a designer who
      # cannot be paid cannot take the work.
      def filtered(scope)
        scope = scope.where("specialties @> ARRAY[?]::varchar[]", [ params[:specialite] ]) if specialty?
        scope = scope.offering(params[:niveau]) if params[:niveau].present?
        scope = scope.accepting if params[:disponibles].present?
        scope
      end

      def specialty? = DesignerProfile::SPECIALTIES.include?(params[:specialite])
  end
end
