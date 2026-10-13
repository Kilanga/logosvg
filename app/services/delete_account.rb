# An administrator deleting an account (asked on 13/10/2026, for accounts
# opened with the wrong address).
#
# The account goes outright when nothing has to outlive it, and its address is
# free again at once. When a print request or a review still names it — a
# workshop's job, a designer's payment — the row stays and is emptied on the
# spot instead (AnonymiseAccount), its shop or profile taken offline. Either
# way the address is released and the person can no longer sign in.
#
# Three refusals, each said in words:
#   - the administrator's own account;
#   - a confirmation that is not the account's address, typed out;
#   - a workshop whose subscription Stripe is still running: deleting here
#     would leave Stripe billing a shop that no longer exists.
class DeleteAccount
  Result = Data.define(:outcome, :reason) do
    def deleted? = outcome == :deleted
    def anonymised? = outcome == :anonymised
    def refused? = outcome == :refused
  end

  # Statuses under which Stripe still bills, or will.
  BILLING_STATUSES = %w[ trialing active past_due ].freeze

  def self.call(...) = new(...).call

  def initialize(user:, by:, confirmation:)
    @user = user
    @by = by
    @confirmation = confirmation.to_s.strip.downcase
  end

  def call
    return refuse(:self) if @user.id == @by.id
    return refuse(:confirmation) unless @confirmation == @user.email_address
    return refuse(:billing) if billing?

    destroy_outright || anonymise
  end

  private
    def refuse(reason) = Result.new(outcome: :refused, reason: reason)

    def billing?
      Subscription.joins(:printer).where(printers: { user_id: @user.id })
                  .where(status: BILLING_STATUSES).exists?
    end

    def destroy_outright
      User.transaction do
        # Counters are bookkeeping, not records: nothing has to outlive them.
        GenerationCounter.where(user_id: @user.id).delete_all
        User.strict_loading(false).find(@user.id).destroy!
      end
      Result.new(outcome: :deleted, reason: nil)
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
      nil
    end

    def anonymise
      User.transaction do
        Printer.where(user_id: @user.id).update_all(status: Printer.statuses[:suspended], updated_at: Time.current)
        DesignerProfile.where(user_id: @user.id).update_all(status: "suspended", updated_at: Time.current)
        AnonymiseAccount.call(User.find(@user.id))
      end
      Result.new(outcome: :anonymised, reason: nil)
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
      refuse(:records)
    end
end
