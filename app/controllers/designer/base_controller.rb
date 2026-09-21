module Designer
  class BaseController < SpaceController
    layout "designer"

    private
      def space_key = :designer_space

      # The signed-in designer's own profile. Same reasoning as
      # `Workshop::BaseController#current_printer`: one query, in the space that
      # needs it, instead of a lazy hop from the current user that development's
      # `strict_loading_by_default` refuses.
      def current_designer_profile
        return @current_designer_profile if defined?(@current_designer_profile)

        @current_designer_profile = DesignerProfile.includes(:review_levels)
                                                   .find_by(user_id: Current.user.id)
      end
      helper_method :current_designer_profile
  end
end
