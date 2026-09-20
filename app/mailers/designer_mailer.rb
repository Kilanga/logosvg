class DesignerMailer < ApplicationMailer
  # Their profile passed review. Said plainly, because until then nothing they
  # do on the platform has any effect.
  def profile_approved(profile)
    @profile = profile
    mail to: profile.user.email_address, subject: t("mailers.designer.profile_approved.subject")
  end

  # Stripe will pay them. This is the moment work can start arriving, so it is
  # worth an email of its own rather than a line on a dashboard.
  def payouts_enabled(profile)
    @profile = profile
    mail to: profile.user.email_address, subject: t("mailers.designer.payouts_enabled.subject")
  end

  # And the other way: work stops arriving without explanation otherwise.
  def payouts_disabled(profile)
    @profile = profile
    mail to: profile.user.email_address, subject: t("mailers.designer.payouts_disabled.subject")
  end
end
