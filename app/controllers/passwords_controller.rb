class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]

  # Resetting a password is proved by holding the emailed token, not by a
  # policy: there is no signed-in user to authorize.
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_password_path, alert: t("flash.rate_limited") }

  def new
  end

  def create
    # Only an active account receives a link, but the answer is the same either
    # way so the form cannot be used to discover which addresses are registered.
    if user = User.active.find_by(email_address: params[:email_address]&.strip&.downcase)
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: t("passwords.create.sent")
  end

  def edit
  end

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      # Every other device is signed out: a reset usually means the password was
      # compromised.
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: t("passwords.update.changed")
    else
      redirect_to edit_password_path(params[:token]), alert: t("passwords.update.mismatch")
    end
  end

  private
    def set_user_by_token
      @user = User.active.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      redirect_to new_password_path, alert: t("passwords.edit.invalid_link")
    end
end
