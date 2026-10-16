module Admin
  # What an administrator checks when something looks wrong.
  class StatusController < BaseController
    # Authorised by SpaceController#authorize_space, like every admin page.
    skip_after_action :verify_policy_scoped

    def show
      @checks = PlatformStatus.call
    end
  end
end
