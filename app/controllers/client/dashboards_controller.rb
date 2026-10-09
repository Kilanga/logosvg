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
      # Whose client this is, and any request still waiting: an account with no
      # shop yet can do nothing else, so this leads the page.
      @workshop = Printer.find_by(id: Current.user.active_workshop_id) if Current.user.active_workshop_id
      # Run out: the dashboard says which shop to scan or ask again.
      @lapsed_workshop = Printer.find_by(id: Current.user.workshop_id) if @workshop.nil? && Current.user.workshop_id
      @pending_affiliation = ClientAffiliation.pending.includes(:printer).find_by(client_id: Current.user.id)
      @workshop_until = Current.user.workshop_until if @workshop
      @workshop_suspended = @workshop && Current.user.workshop_period_suspended?
    end
  end
end
