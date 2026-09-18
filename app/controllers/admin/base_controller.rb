module Admin
  class BaseController < SpaceController
    layout "admin"

    private
      def space_key = :admin_space
  end
end
