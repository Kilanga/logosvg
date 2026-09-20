require "test_helper"

module Payments
  # `payouts_enabled` is Stripe's word and is never inferred: a designer who
  # filled in every field but is still under review cannot be paid.
  class SyncConnectAccountTest < ActiveSupport::TestCase
    test "Stripe turning payouts on is copied over, and the designer is told" do
      leo = designer_profiles(:leo)

      assert_emails 1 do
        SyncConnectAccount.call(profile: leo, account: account(payouts_enabled: true))
      end

      assert_predicate leo.reload, :payouts_enabled?
      assert_predicate leo, :can_take_work?
    end

    # Work simply stops arriving otherwise, with no explanation.
    test "Stripe turning payouts off is copied over too, and said out loud" do
      ines = designer_profiles(:ines)

      assert_emails 1 do
        SyncConnectAccount.call(profile: ines, account: account(payouts_enabled: false))
      end

      assert_not_predicate ines.reload, :payouts_enabled?
      assert_not_predicate ines, :can_take_work?
    end

    # Stripe repeats itself freely; the designer's inbox should not.
    test "an account event that changes nothing sends no email" do
      assert_no_emails do
        SyncConnectAccount.call(profile: designer_profiles(:ines), account: account(payouts_enabled: true))
      end
    end

    test "a missing flag is read as not payable rather than as unchanged" do
      ines = designer_profiles(:ines)

      SyncConnectAccount.call(profile: ines, account: { id: "acct_test_ines" })

      assert_not_predicate ines.reload, :payouts_enabled?
    end

    # Being payable is not the same as being vetted: both gates stand.
    test "payouts alone do not publish an unvetted profile" do
      nour = designer_profiles(:nour)

      SyncConnectAccount.call(profile: nour, account: account(payouts_enabled: true))

      assert_predicate nour.reload, :pending_review?
      assert_not_predicate nour, :can_take_work?
    end

    private
      def account(payouts_enabled:)
        { id: "acct_test", payouts_enabled: payouts_enabled, charges_enabled: payouts_enabled }
      end
  end
end
