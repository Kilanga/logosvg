module Public
  # The legal pages.
  #
  # One action, one template per document. The `page` comes from the route
  # rather than from the request, so there is no path a visitor can type that
  # renders something else.
  class LegalController < BaseController
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped

    PAGES = %w[ legal_notice terms subscription_terms designer_terms privacy ranking ].freeze

    def show
      page = params[:page]
      raise ActionController::RoutingError, "unknown legal page" unless PAGES.include?(page)

      @page = page
      render "public/legal/#{page}"
    end
  end
end
