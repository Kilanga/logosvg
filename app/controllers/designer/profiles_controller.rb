module Designer
  # The designer's own profile: who they are, what they do, and which levels
  # they take.
  #
  # There is no "submit" step: a profile exists in `pending_review` from the
  # moment it is created, and an administrator activates it. That is why the
  # "enough to be judged" checks live in the `:activation` context rather than
  # running on every save — a designer writing their page over three sittings
  # must be able to save it half-finished.
  class ProfilesController < BaseController
    skip_after_action :verify_policy_scoped

    before_action :set_profile

    def edit
      authorize @profile, :edit?
    end

    def update
      authorize @profile, :update?

      @profile.assign_attributes(profile_params)
      apply_levels

      if @profile.save
        redirect_to edit_designer_profile_path, notice: t(".saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private
      # A designer who has never filled anything in still gets a form.
      def set_profile
        @profile = current_designer_profile ||
                   Current.user.build_designer_profile(display_name: Current.user.full_name)
      end

      # The levels arrive as a set of checkboxes, so the whole set is rewritten
      # rather than patched: unchecking one has to remove it.
      def apply_levels
        chosen = Array(params.dig(:designer_profile, :review_level_ids)).compact_blank.map(&:to_i)
        # Absent means "not part of this submission", not "none".
        return if params.dig(:designer_profile, :review_level_ids).nil?

        @profile.review_level_ids = ReviewLevel.offered.where(id: chosen).pluck(:id)
      end

      def profile_params
        params.expect(designer_profile: [
          :display_name, :bio, :city, :remote, :accepting_work, :avatar,
          { specialties: [], languages: [], portfolio: [] }
        ])
      end
  end
end
