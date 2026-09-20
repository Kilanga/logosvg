module Admin
  # What an administrator checks when something looks wrong.
  class StatusController < BaseController
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped

    def show
      @checks = PlatformStatus.call
    end
  end
end
