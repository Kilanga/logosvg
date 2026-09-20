module Admin
  # The terms the platform will not draw.
  #
  # Deactivating rather than deleting is the usual move: a term that stops
  # being needed is worth keeping with its hit count, in case the question
  # comes back.
  class BlockedTermsController < BaseController
    def index
      @terms = policy_scope(BlockedTerm, policy_scope_class: BlockedTermPolicy::Scope).by_usage
      @term = BlockedTerm.new
      authorize BlockedTerm
    end

    def create
      @term = BlockedTerm.new(term_params.merge(created_by: Current.user))
      authorize @term

      if @term.save
        redirect_to admin_blocked_terms_path, notice: t(".added", term: @term.term)
      else
        @terms = BlockedTerm.by_usage
        render :index, status: :unprocessable_entity
      end
    end

    def update
      @term = BlockedTerm.find(params[:id])
      authorize @term

      @term.update!(active: !@term.active?)
      redirect_to admin_blocked_terms_path,
                  notice: t(".#{@term.active? ? 'activated' : 'deactivated'}", term: @term.term)
    end

    def destroy
      @term = BlockedTerm.find(params[:id])
      authorize @term

      @term.destroy!
      redirect_to admin_blocked_terms_path, notice: t(".removed", term: @term.term)
    end

    private
      def term_params = params.expect(blocked_term: [ :term, :reason ])
  end
end
