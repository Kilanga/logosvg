# The address of a new account, checked before it can generate, send, pay or
# subscribe (decided on 11/10/2026). See RequireVerifiedEmail.
class AccountMailer < ApplicationMailer
  def verify_email(user)
    @user = user
    @token = user.generate_token_for(:email_verification)

    mail to: user.email_address, subject: t("mailers.account.verify_email.subject")
  end
end
