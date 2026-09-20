module Designer
  # Designer dashboard. What it shows above all else is what stands between
  # this designer and being given work — step 8 fills the queue below it.
  class DashboardsController < BaseController
    skip_after_action :verify_policy_scoped

    def show
      @profile = Current.user.designer_profile
    end
  end
end
