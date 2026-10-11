# The link in the verification email (decided on 11/10/2026).
#
# Opening the link only shows a page; its button verifies. Mail scanners open
# every link they find, and the address is proved by the person who reads the
# email, not by a robot that fetched it. Same rule as the print request
# confirmation.
class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access only: %i[ show update ]
  before_action :set_user_by_token, only: %i[ show update ]

  # Proved by holding the emailed token, or, for a new email, by being the
  # signed-in owner of the account: no record to authorize.
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  # Each email counts against the day's Brevo sends: a few tries, no more.
  rate_limit to: 3, within: 10.minutes, only: :create, by: -> { Current.user&.id || request.remote_ip },
             with: -> { redirect_back_or_to fallback_path, alert: t("flash.rate_limited"), status: :see_other }

  def show
  end

  def update
    if @user.verify_email!
      notify_pending_workshop(@user)
    end

    if Current.user == @user
      redirect_to space_path_for(@user), notice: t(".verified")
    else
      redirect_to new_session_path, notice: t(".verified_sign_in")
    end
  end

  # Another email, for an address not yet verified.
  def create
    if Current.user.email_verified?
      redirect_back_or_to space_path_for(Current.user), notice: t(".already"), status: :see_other
    else
      AccountMailer.verify_email(Current.user).deliver_later
      redirect_back_or_to space_path_for(Current.user),
                          notice: t(".sent", email: Current.user.email_address), status: :see_other
    end
  end

  private
    def set_user_by_token
      @user = User.active.find_by_token_for(:email_verification, params[:token])
      return if @user

      if Current.user&.email_verified?
        redirect_to space_path_for(Current.user), notice: t("email_verifications.update.verified")
      else
        redirect_to(Current.user ? space_path_for(Current.user) : new_session_path,
                    alert: t("email_verifications.show.invalid_link"))
      end
    end

    # A request to a workshop waits for the address: the shop is written to
    # only about someone who can be written back to.
    def notify_pending_workshop(user)
      ClientAffiliation.pending.from_request.where(client_id: user.id).find_each do |affiliation|
        AffiliationMailer.requested(affiliation).deliver_later
      end
    end
end
