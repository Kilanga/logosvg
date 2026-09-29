module Public
  # The answer to "may we remember which workshop sent you?": from the banner,
  # and from the cookies page, which is where it can be changed afterwards.
  #
  # Refusing is one click, like accepting, and so is changing one's mind: a
  # choice that is hard to take back is not a choice.
  class CookieConsentsController < BaseController
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped

    def create
      case params[:choice]
      when "accepted"
        shop_context.accept!
        notice = t(".accepted")
      when "declined"
        shop_context.decline!
        notice = t(".declined")
      else
        return redirect_back_or_to(cookies_path, alert: t(".unknown"))
      end

      redirect_back_or_to cookies_path, notice: notice
    end
  end
end
