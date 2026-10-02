require "test_helper"

class ContactTest < ActionDispatch::IntegrationTest
  test "a visitor reads the contact page without an account" do
    get contact_path

    assert_response :success
    assert_select "a[href=?]", "mailto:#{Rails.application.config.tshirt.support_email}"
  end

  test "the contact page is reachable from every page's footer" do
    get root_path

    assert_select "a[href=?]", contact_path
  end
end
