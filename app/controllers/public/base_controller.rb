module Public
  # Pages a visitor may read without an account: home, the printer directory and
  # shop pages, the designer list. They show no user-owned data, so they are the
  # only controllers allowed to skip authorization.
  class BaseController < ApplicationController
    allow_unauthenticated_access
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped
  end
end
