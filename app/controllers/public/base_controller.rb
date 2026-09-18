module Public
  # Pages a visitor may read without an account: home, the printer directory and
  # shop pages, the designer list.
  #
  # Authorization is not skipped here: the directory still goes through
  # `policy_scope`, so what a visitor sees is decided in one place. Only pages
  # showing no records at all opt out, and they say so themselves.
  class BaseController < ApplicationController
    allow_unauthenticated_access
  end
end
