module Designer
  # Where a designer sets up getting paid, and where they go to read about it.
  #
  # The platform holds no bank detail and sees no identity document: Connect
  # Express hosts the whole of it, and what comes back is one boolean.
  class PayoutsController < BaseController
    skip_after_action :verify_policy_scoped

    before_action :set_profile

    def show
      authorize @profile, :show?
    end

    # Opens — or resumes — Stripe's onboarding. The link is single-use and
    # short-lived by Stripe's design, so a fresh one is minted every time.
    def onboard
      authorize @profile, :onboard?

      result = Payments::ConnectOnboarding.call(
        profile: @profile,
        return_url: designer_payouts_url(retour: 1),
        refresh_url: designer_payouts_url
      )

      if result.success?
        redirect_to result.url, allow_other_host: true
      else
        redirect_to designer_payouts_path, alert: result.error
      end
    end

    # Stripe's own dashboard, where a designer reads their payouts.
    def dashboard
      authorize @profile, :onboard?

      if @profile.stripe_account_id.blank?
        return redirect_to designer_payouts_path, alert: t(".no_account")
      end

      link = Payments::StripeClient.new.create_login_link(account: @profile.stripe_account_id)
      redirect_to link.url, allow_other_host: true
    rescue Payments::StripeClient::NotConfigured
      redirect_to designer_payouts_path, alert: t("designers.errors.not_configured")
    rescue Payments::StripeClient::Failed => e
      Rails.logger.error("[stripe] #{e.message}")
      redirect_to designer_payouts_path, alert: t("designers.errors.unavailable")
    end

    private
      def set_profile
        @profile = current_designer_profile ||
                   Current.user.build_designer_profile(display_name: Current.user.full_name)
      end
  end
end
