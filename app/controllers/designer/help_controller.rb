module Designer
  # The designer's help (decided on 09/10/2026): how a review runs, how and
  # when they are paid, disputes and custom jobs. Nothing here is a record of
  # anyone's: the space check in SpaceController is the authorization.
  class HelpController < BaseController
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped

    def show; end
  end
end
