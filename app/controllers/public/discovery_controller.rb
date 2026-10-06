module Public
  # What search engines and browsers ask for by convention: robots.txt, the
  # sitemap, and /favicon.ico.
  #
  # robots.txt is rendered rather than static so that it can name the sitemap
  # with the host the application actually serves, which lives in one place
  # (APP_HOST). The sitemap lists only what a visitor may already read: the
  # public pages, and the directory entries `policy_scope` lets through.
  class DiscoveryController < BaseController
    skip_after_action :verify_authorized

    def robots
      skip_policy_scope
      render plain: render_to_string(template: "public/discovery/robots", formats: :text),
             content_type: "text/plain"
    end

    def sitemap
      @printers = policy_scope(Printer).select(:id, :slug, :updated_at)
      @designers = policy_scope(DesignerProfile).select(:id, :updated_at)
      render formats: :xml
    end

    # Browsers ask for it whatever the page says; the icon itself is the PNG
    # every layout already links.
    def favicon
      skip_policy_scope
      redirect_to "/icon.png", status: :moved_permanently
    end
  end
end
