module Client
  class BaseController < SpaceController
    layout "client"

    private
      def space_key = :client_space
  end
end
