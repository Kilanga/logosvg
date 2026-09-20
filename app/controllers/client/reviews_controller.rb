module Client
  # The client's designer reviews.
  #
  # The list exists and is drawn before there is anything to put in it: step 8
  # brings the Review model, the payment and the designer side. Having the
  # screen now means the space is whole, and that the empty state is designed
  # rather than discovered later.
  class ReviewsController < BaseController
    skip_after_action :verify_policy_scoped

    def index
    end
  end
end
