require "test_helper"

class AccountLifecycleTest < ActionDispatch::IntegrationTest
  # --- Export ---------------------------------------------------------------

  test "a client downloads everything the platform holds about them" do
    sign_in_as users(:client)

    get client_account_export_path

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])

    data = JSON.parse(response.body)

    assert_equal users(:client).email_address, data.dig("account", "email")
    assert data["designs"].any?
  end

  test "an export carries nobody else's data" do
    sign_in_as users(:client)

    get client_account_export_path

    references = JSON.parse(response.body)["designs"].map { |d| d["reference"] }

    assert_not_includes references, designs(:other_client_design).token
  end

  test "a visitor exports nothing" do
    get client_account_export_path

    assert_redirected_to new_session_path
  end

  # --- Closing an account ---------------------------------------------------

  test "a client closes their account with their password in hand" do
    sign_in_as users(:client)

    delete client_account_path, params: { current_password: "motdepasse-test" }

    assert_redirected_to root_path
    assert_not_predicate users(:client).reload, :active?
  end

  # The case this guards: a browser left open and unattended.
  test "a wrong password closes nothing" do
    sign_in_as users(:client)

    delete client_account_path, params: { current_password: "pas-le-bon" }

    assert_response :unprocessable_entity
    assert_predicate users(:client).reload, :active?
  end

  test "closing an account ends every session it had" do
    other = users(:client).sessions.create!
    sign_in_as users(:client)

    delete client_account_path, params: { current_password: "motdepasse-test" }

    assert_not Session.exists?(other.id)
  end

  test "a closed account can no longer sign in" do
    sign_in_as users(:client)
    delete client_account_path, params: { current_password: "motdepasse-test" }
    sign_out

    assert_no_difference "Session.count" do
      post session_path, params: { email_address: "claire@example.invalid",
                                   password: "motdepasse-test" }
    end

    assert_redirected_to new_session_path
  end

  # What a workshop has in hand is its record too.
  test "closing an account leaves a sent print request standing" do
    sign_in_as users(:client)

    delete client_account_path, params: { current_password: "motdepasse-test" }

    assert PrintRequest.exists?(print_requests(:waiting).id)
  end

  # --- Legal pages ----------------------------------------------------------

  test "every legal page is readable without an account" do
    [ legal_notice_path, terms_path, subscription_terms_path,
      designer_terms_path, privacy_path, ranking_path ].each do |path|
      get path

      assert_response :success, "#{path} must be public"
      assert_select "h1"
    end
  end

  test "each one links to the others" do
    get privacy_path

    assert_select "a[href=?]", terms_path
    assert_select "a[href=?]", ranking_path
  end

  test "the footer carries them on every public page" do
    get root_path

    assert_select "a[href=?]", legal_notice_path
    assert_select "a[href=?]", privacy_path
  end

  # The spec asks for the ranking to be explained, not merely disclosed.
  test "the ranking page says the highlight is paid for" do
    get ranking_path

    assert_select "body", text: /#{Regexp.escape(I18n.t('legal.ranking.featured.title'))}/i
  end

  # Said out loud rather than a page that looks finished and is not.
  test "the legal pages say they are drafts" do
    get terms_path

    assert_select "body", text: /#{Regexp.escape(I18n.t('legal.draft_title'))}/i
  end

  # --- Accessibility --------------------------------------------------------
  #
  # Checked where it is cheap to check and easy to lose: the document's
  # language, a way past the navigation, and a name on every form control.

  # No failure messages here: `assert_select` reads a further positional
  # argument as text to match, not as a message.
  test "every page declares its language and offers a skip link" do
    [ root_path, printers_path, designers_path, terms_path ].each do |path|
      get path

      assert_select "html[lang=?]", "fr"
      assert_select "a.skip-link[href=?]", "#contenu"
      assert_select "main#contenu"
    end
  end

  # Three ways a control is named, and all three count: a `for` attribute, a
  # label wrapped around it, or an explicit `aria-label`.
  test "every form control on the creation screen has a label" do
    sign_in_as users(:client)

    get new_design_path

    assert_select "input, select, textarea" do |controls|
      controls.each do |control|
        next if control["type"].in?(%w[ hidden submit ])

        assert named?(control), "le champ #{control['id'] || control['name']} n'a pas de libellé"
      end
    end
  end

  test "images that carry no information are hidden from screen readers" do
    designs(:fox_screen).print_file.attach(
      io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml"
    )
    sign_in_as users(:client)

    get client_designs_path

    assert_select "img" do |images|
      images.each { |image| assert_not_nil image["alt"], "une image sans attribut alt" }
    end
  end

  private
    def named?(control)
      return true if control["aria-label"].present?
      return true if control["id"].present? && css_select("label[for='#{control['id']}']").any?

      # Wrapped: `<label>…<input></label>` names the control without a `for`.
      control.ancestors("label").any?
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="#000"/></svg>)
    end
end
