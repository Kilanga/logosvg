class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    @token = user.password_reset_token
    mail to: user.email, subject: t("mailers.passwords.reset.subject")
  end
end
