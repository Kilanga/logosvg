# Until its address is verified, an account signs in and looks around, but
# does nothing that writes to someone or costs something: generate, convert a
# file, send to a workshop, pay for a review, subscribe, submit a shop for
# review, take a review, open payouts, ask a workshop (decided on 11/10/2026).
#
#   require_verified_email only: %i[ create ]
#
# Declared in each controller, next to the actions it guards: a list kept in
# one place would drift from the controllers it names.
module RequireVerifiedEmail
  extend ActiveSupport::Concern

  class_methods do
    def require_verified_email(**options)
      before_action :require_verified_email!, **options
    end
  end

  private
    def require_verified_email!
      return if Current.user.nil? || Current.user.email_verified?

      redirect_back_or_to space_path_for(Current.user),
                          alert: t("email_verifications.required"), status: :see_other
    end
end
