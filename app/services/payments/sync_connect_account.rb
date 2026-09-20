module Payments
  # Copies what Stripe decided about a designer's account onto their profile.
  #
  # `payouts_enabled` is Stripe's word and is never inferred: a designer who
  # filled in every field but is still under review cannot be paid, and so
  # cannot be given work.
  class SyncConnectAccount
    def self.call(...) = new(...).call

    def initialize(profile:, account:)
      @profile = profile
      @account = account
    end

    def call
      was_enabled = @profile.payouts_enabled?
      now_enabled = @account[:payouts_enabled].present?

      @profile.update!(payouts_enabled: now_enabled)

      # Told when it turns on — that is the moment they can start working —
      # and when it turns off, because work stops arriving without explanation
      # otherwise.
      notify(was_enabled, now_enabled)
      @profile
    end

    private
      def notify(was_enabled, now_enabled)
        return if was_enabled == now_enabled

        if now_enabled
          DesignerMailer.payouts_enabled(@profile).deliver_later
        else
          DesignerMailer.payouts_disabled(@profile).deliver_later
        end
      end
  end
end
