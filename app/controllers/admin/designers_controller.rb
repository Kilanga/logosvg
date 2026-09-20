module Admin
  # Designer profiles waiting for a decision, and the decision itself.
  class DesignersController < BaseController
    def index
      @designers = policy_scope(DesignerProfile, policy_scope_class: DesignerProfilePolicy::AdminScope)
                     .includes(:user, :review_levels)
                     .with_attached_avatar
                     .order(Arel.sql("CASE status WHEN 'pending_review' THEN 0 ELSE 1 END"),
                            updated_at: :desc)
    end

    def update
      @designer = DesignerProfile.find(params[:id])
      authorize @designer, :approve?

      if activating? then activate else suspend end
    end

    private
      def activating? = requested_status == "active"

      # Activating runs the "enough to be judged" checks: an administrator
      # cannot publish a profile with no bio and no levels, however they got
      # to this button.
      def activate
        if @designer.ready_for_activation? && @designer.update(status: "active")
          DesignerMailer.profile_approved(@designer).deliver_later
          redirect_to admin_designers_path, notice: t(".active", name: @designer.display_name)
        else
          redirect_to admin_designers_path, alert: t(".incomplete", name: @designer.display_name)
        end
      end

      def suspend
        @designer.update!(status: "suspended")
        redirect_to admin_designers_path, notice: t(".suspended", name: @designer.display_name)
      end

      # Only the two decisions an administrator makes.
      def requested_status
        %w[ active suspended ].find { |s| s == params[:status] } ||
          raise(ActionController::BadRequest)
      end
  end
end
