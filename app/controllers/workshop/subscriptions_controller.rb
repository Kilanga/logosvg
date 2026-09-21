module Workshop
  # The shop's own subscription: which plan it is on, and two buttons.
  #
  # Changing plan, changing card and reading invoices all happen in Stripe's
  # customer portal. Rebuilding any of that here would mean holding card data
  # and invoice history we have no reason to hold.
  class SubscriptionsController < BaseController
    skip_after_action :verify_policy_scoped

    before_action :set_printer

    def show
      authorize @printer, :update?
      @subscription = @printer.subscription
    end

    def create
      authorize @printer, :update?

      result = Payments::StartSubscription.call(
        printer: @printer,
        plan: params[:plan],
        success_url: workshop_subscription_url(souscrit: 1),
        cancel_url: workshop_subscription_url
      )

      if result.success?
        # `allow_other_host`: Checkout is on Stripe's domain, which is the
        # whole point of redirecting there.
        redirect_to result.url, allow_other_host: true
      else
        redirect_to workshop_subscription_path, alert: result.error
      end
    end

    def portal
      authorize @printer, :update?

      subscription = @printer.subscription
      if subscription&.stripe_customer_id.blank?
        return redirect_to workshop_subscription_path, alert: t(".no_customer")
      end

      session = Payments::StripeClient.new.create_portal_session(
        customer: subscription.stripe_customer_id, return_url: workshop_subscription_url
      )

      redirect_to session.url, allow_other_host: true
    rescue Payments::StripeClient::NotConfigured
      redirect_to workshop_subscription_path, alert: t("subscriptions.errors.not_configured")
    rescue Payments::StripeClient::Failed => e
      Rails.logger.error("[stripe] #{e.message}")
      redirect_to workshop_subscription_path, alert: t("subscriptions.errors.unavailable")
    end

    private
      def set_printer
        @printer = current_printer || Printer.new(user: Current.user)
      end
  end
end
