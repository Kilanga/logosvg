require "application_system_test_case"

class ClientSpaceTest < ApplicationSystemTestCase
  setup do
    [ designs(:fox_screen), designs(:fox_dtf) ].each do |design|
      design.print_file.attach(
        io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml"
      )
    end
  end

  # The client walks their own space from one screen to the next.
  test "a client crosses their space from the dashboard" do
    sign_in users(:client)

    assert_selector "h1", text: displayed("client.dashboards.show.heading", name: "Claire")
    assert_text displayed("client.dashboards.show.waiting_on_you")

    click_on I18n.t("nav.my_designs")

    assert_selector "h1", text: displayed("client.designs.index.heading")
    assert_text shown(designs(:fox_screen).prompt)

    click_on I18n.t("nav.my_requests")

    assert_selector "h1", text: displayed("client.print_requests.index.heading")
    assert_text shown(printers(:rennes).name)

    click_on I18n.t("nav.my_reviews")

    assert_text displayed("client.reviews.index.empty")

    click_on I18n.t("nav.my_account")

    assert_field "user_first_name", with: "Claire"
  end

  # A variant is another take on the same idea, not another idea.
  test "variants sit inside their lineage's card, not beside it" do
    CreateDesignChildren.call(parent: designs(:fox_screen)) do
      { "job_ids" => %w[ v1 v2 ], "job_id" => "v1" }
    end
    Design.where(generator_job_id: %w[ v1 v2 ]).find_each do |variant|
      variant.print_file.attach(
        io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml"
      )
      variant.succeed!
      variant.save!
    end

    sign_in users(:client)
    visit client_designs_path

    assert_text displayed("client.designs.index.variants", count: 2)
    assert_selector "li.panel", count: Design.active.roots.where(user: users(:client)).count
  end

  test "a client deletes a design from the list" do
    sign_in users(:client)
    visit client_designs_path

    # Both fixture designs share a prompt, so the card is found by its link
    # rather than by its words.
    card = first("a[href='#{design_path(designs(:fox_dtf))}']").ancestor("li.panel")

    within(card) do
      accept_confirm { click_on I18n.t("client.designs.index.delete") }
    end

    assert_text displayed("client.designs.destroy.deleted")
    assert_not_predicate designs(:fox_dtf).reload, :active?
  end

  test "a client corrects their details" do
    sign_in users(:client)
    visit client_account_path

    fill_in "user_city", with: "Saint-Malo"
    click_on I18n.t("client.accounts.edit.save")

    assert_text displayed("client.accounts.update.saved")
    assert_equal "Saint-Malo", users(:client).reload.city
  end

  # Asked for even though the visitor is signed in: an unattended browser is
  # the case this guards against.
  test "changing a password needs the current one" do
    sign_in users(:client)
    visit client_account_path

    fill_in "user_current_password", with: "pas-le-bon"
    fill_in "user_password", with: "un-nouveau-mot-de-passe"
    fill_in "user_password_confirmation", with: "un-nouveau-mot-de-passe"
    click_on I18n.t("client.accounts.edit.change_password")

    assert_text shown(I18n.t("activerecord.errors.models.user.attributes.current_password.invalid"))
    assert users(:client).reload.authenticate("motdepasse-test")

    fill_in "user_current_password", with: "motdepasse-test"
    fill_in "user_password", with: "un-nouveau-mot-de-passe"
    fill_in "user_password_confirmation", with: "un-nouveau-mot-de-passe"
    click_on I18n.t("client.accounts.edit.change_password")

    assert_text displayed("client.accounts.update_password.changed")
    assert users(:client).reload.authenticate("un-nouveau-mot-de-passe")
  end

  # The empty states are drawn, not left to the browser.
  test "a client with nothing yet is shown drawn empty states" do
    # This account owns one design in the fixtures; an empty space needs it
    # gone as well as the account reopened.
    users(:deleted_client).update!(deleted_at: nil)
    designs(:other_client_design).soft_delete!
    sign_in users(:deleted_client)

    visit client_designs_path

    assert_text displayed("client.designs.index.empty")
    assert_link I18n.t("nav.create")

    visit client_print_requests_path

    assert_text displayed("client.print_requests.index.empty")
  end

  private
    def sign_in(user)
      visit new_session_path
      fill_in I18n.t("activerecord.attributes.user.email_address"), with: user.email_address
      fill_in I18n.t("activerecord.attributes.user.password"), with: "motdepasse-test"
      click_on I18n.t("sessions.new.submit")

      assert_no_current_path new_session_path
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 10 10">) +
        %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>)
    end
end
