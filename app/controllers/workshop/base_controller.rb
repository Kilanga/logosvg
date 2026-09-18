module Workshop
  class BaseController < SpaceController
    layout "workshop"

    private
      def space_key = :workshop_space
  end
end
