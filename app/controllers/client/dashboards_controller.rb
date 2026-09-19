module Client
  # Client dashboard: what is waiting on them first, then what has been
  # happening. The lists themselves live on their own screens.
  class DashboardsController < BaseController
    # Nothing on this page is a record the client could fail to own — every
    # list is built from `Current.user`'s own associations. The space check in
    # SpaceController is the authorization.
    skip_after_action :verify_policy_scoped

    def show
      @dashboard = ClientDashboard.call(client: Current.user)
    end
  end
end
