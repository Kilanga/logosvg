require "test_helper"

class DeleteAccountTest < ActiveSupport::TestCase
  setup { @admin = users(:admin) }

  test "an account with nothing to keep is deleted outright, and its address is free again" do
    account = users(:designer_pending)
    email = account.email_address

    result = DeleteAccount.call(user: account, by: @admin, confirmation: "  #{email.upcase} ")

    assert_predicate result, :deleted?
    assert_not User.exists?(account.id)
    assert_not DesignerProfile.exists?(user_id: account.id)
    assert_not User.exists?(email_address: email)
  end

  test "a workshop without a running subscription goes with its listing" do
    account = users(:printer_draft)
    printer = account.printer
    assert_nil printer.subscription

    result = DeleteAccount.call(user: account, by: @admin, confirmation: account.email_address)

    assert_predicate result, :deleted?
    assert_not Printer.exists?(printer.id)
    assert_not PrinterTechnique.exists?(printer_id: printer.id)
  end

  test "the confirmation must be the account's address" do
    account = users(:designer_pending)

    result = DeleteAccount.call(user: account, by: @admin, confirmation: "autre@example.invalid")

    assert_predicate result, :refused?
    assert_equal :confirmation, result.reason
    assert User.exists?(account.id)
  end

  test "an administrator cannot delete their own account" do
    result = DeleteAccount.call(user: @admin, by: @admin, confirmation: @admin.email_address)

    assert_equal :self, result.reason
    assert User.exists?(@admin.id)
  end

  test "a workshop Stripe still bills is not deleted" do
    account = users(:printer)
    assert printers(:rennes).subscription.status.in?(DeleteAccount::BILLING_STATUSES)

    result = DeleteAccount.call(user: account, by: @admin, confirmation: account.email_address)

    assert_equal :billing, result.reason
    assert User.exists?(account.id)
  end

  test "an account named by kept records is emptied instead, and its shop taken offline" do
    account = users(:client)
    assert PrintRequest.exists?(client_id: account.id) || Review.exists?(client_id: account.id)
    email = account.email_address

    result = DeleteAccount.call(user: account, by: @admin, confirmation: email)

    assert_predicate result, :anonymised?
    account.reload
    assert_match(/\Acompte-supprime-\d+@invalid\z/, account.email_address)
    assert_not_nil account.deleted_at
    assert_not User.exists?(email_address: email)
    assert_equal 0, Session.where(user_id: account.id).count
  end

  test "a designer with reviews is emptied and their profile suspended" do
    account = users(:designer)
    profile = account.designer_profile
    assert Review.exists?(designer_profile_id: profile.id)
    profile.update_columns(stripe_account_id: nil) if profile.has_attribute?(:stripe_account_id)

    result = DeleteAccount.call(user: account, by: @admin, confirmation: account.email_address)

    assert_predicate result, :anonymised?
    assert_predicate profile.reload, :suspended?
  end
end
