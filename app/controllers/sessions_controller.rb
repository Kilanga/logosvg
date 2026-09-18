class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]

  # A session is not a record someone owns: whoever presents valid credentials
  # may open one. There is nothing for a policy to decide here.
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_session_path, alert: t("flash.rate_limited") }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to after_authentication_url
    else
      # Deliberately the same wording whether the address is unknown or the
      # password is wrong: the form must not reveal which accounts exist.
      redirect_to new_session_path, alert: t("sessions.create.failed")
    end
  end

  def destroy
    terminate_session
    redirect_to root_path, status: :see_other, notice: t("sessions.destroy.signed_out")
  end

  private
    # Back to where they were heading, otherwise to their own space.
    def after_authentication_url
      session.delete(:return_to_after_authenticating) || space_path_for(Current.user)
    end
end
