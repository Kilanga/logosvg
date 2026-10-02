module Public
  # Nowhere to send one email and a different place to send a complaint: the
  # same address does both, and the page says so plainly.
  class ContactController < BaseController
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped

    def show
    end
  end
end
