module Public
  # Landing page aimed at print shops: what the platform does for them, how it
  # works, what the order email looks like, and the two subscription plans.
  #
  # Shows no records, so there is nothing to authorize or to scope.
  class HomeController < BaseController
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped

    def show
    end
  end
end
