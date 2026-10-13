require "test_helper"

# Asked on 13/10/2026: delete an account from the administration, confirming
# by typing its address.
class AdminAccountsTest < ActionDispatch::IntegrationTest
  test "an administrator finds an account and deletes it by typing its address" do
    account = users(:designer_pending)
    sign_in_as users(:admin)

    get admin_accounts_path, params: { q: account.email_address }
    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(account)} a[href=?]",
                  confirm_destroy_admin_account_path(account)

    get confirm_destroy_admin_account_path(account)
    assert_response :success

    delete admin_account_path(account), params: { confirmation: account.email_address }

    assert_redirected_to admin_accounts_path
    assert_equal I18n.t("admin.accounts.destroy.deleted", email: account.email_address), flash[:notice]
    assert_not User.exists?(account.id)
  end

  test "a wrong address deletes nothing and says so" do
    account = users(:designer_pending)
    sign_in_as users(:admin)

    delete admin_account_path(account), params: { confirmation: "pas-la-bonne@example.invalid" }

    assert_response :unprocessable_entity
    assert_select "body", text: /#{Regexp.escape(I18n.t("admin.accounts.destroy.refused.confirmation",
                                                         email: account.email_address))}/
    assert User.exists?(account.id)
  end

  test "the administrator's own account offers no delete button" do
    admin = users(:admin)
    sign_in_as admin

    get admin_accounts_path, params: { q: admin.email_address }

    assert_select "##{ActionView::RecordIdentifier.dom_id(admin)} a[href=?]",
                  confirm_destroy_admin_account_path(admin), count: 0
  end

  test "nobody else reaches the accounts screen or deletes anything" do
    account = users(:designer_pending)
    sign_in_as users(:printer)

    get admin_accounts_path
    assert_response :redirect

    delete admin_account_path(account), params: { confirmation: account.email_address }
    assert User.exists?(account.id)
  end
end
