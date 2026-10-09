module Workshop
  # The workshop's help: how the site works for it, its questions, and a sheet
  # it hands to its clients (decided on 09/10/2026). Nothing here is a record
  # of anyone's: the space check in SpaceController is the authorization.
  class HelpController < BaseController
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped

    def show; end
  end
end
