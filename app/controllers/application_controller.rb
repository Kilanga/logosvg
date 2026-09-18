class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Every action states who may run it, and every listing states which records
  # the signed-in user may see. Forgetting either raises instead of leaking.
  #
  # Conditions rather than `only:`/`except:`: naming an action a controller does
  # not have raises under raise_on_missing_callback_actions, and most
  # controllers here have no index.
  after_action :verify_authorized, unless: :listing?
  after_action :verify_policy_scoped, if: :listing?

  rescue_from Pundit::NotAuthorizedError, with: :deny_access

  helper_method :space_path_for

  private
    def listing? = action_name == "index"

    # Pundit reads the current user from here rather than from `current_user`.
    def pundit_user = Current.user

    # Reached only when someone signed in tries to open a space that is not
    # theirs: an unauthenticated visitor is sent to the sign-in page earlier, by
    # the Authentication concern.
    def deny_access
      respond_to do |format|
        format.html { redirect_to fallback_path, alert: t("flash.unauthorized") }
        format.any { head :forbidden }
      end
    end

    def fallback_path
      Current.user ? space_path_for(Current.user) : root_path
    end

    # Where a signed-in user belongs. An administrator never uses another role's
    # space, so each role has exactly one home.
    def space_path_for(user)
      case user&.role
      when "client"   then client_dashboard_path
      when "printer"  then printer_dashboard_path
      when "designer" then designer_dashboard_path
      when "admin"    then admin_dashboard_path
      else root_path
      end
    end
end
