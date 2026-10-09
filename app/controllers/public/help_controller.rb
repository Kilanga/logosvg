module Public
  # `/aide` — the clients' questions. Public: a visitor deciding whether to
  # create an account reads it as much as a client who already has one.
  class HelpController < BaseController
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped

    def show; end
  end
end
