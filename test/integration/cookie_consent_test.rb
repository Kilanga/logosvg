require "test_helper"

class CookieConsentTest < ActionDispatch::IntegrationTest
  BROWSER = { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Safari/605.1.15" }.freeze
  SHOP = "Presse Rhône".freeze

  setup { @lyon = printers(:lyon) }

  # --- Nothing is set before an answer ------------------------------------------------

  test "scanning a poster sets no cookie beyond the session" do
    scan

    assert_nil cookies[:shop_ref]
    assert_nil cookies[:cookie_consent]
  end

  test "the session still knows the shop, so the site works without any answer" do
    scan
    sign_in_as users(:client)

    get new_design_path

    assert_select "body", text: /#{SHOP}/i
  end

  # --- The banner ---------------------------------------------------------------------

  test "a visitor a shop sent is asked, with both answers on offer" do
    scan
    sign_in_as users(:client)

    get new_design_path

    assert_select "section[aria-labelledby=consent-title]" do
      assert_select "form[action=?]", cookie_consent_path, count: 2
      assert_select "input[name=choice][value=declined]"
      assert_select "input[name=choice][value=accepted]"
      assert_select "a[href=?]", cookies_path
    end
  end

  test "a visitor who came by the front door is asked nothing" do
    get root_path

    assert_select "section[aria-labelledby=consent-title]", count: 0
  end

  test "the banner is not shown on the cookies page, which asks in full" do
    scan

    get cookies_path

    assert_select "section[aria-labelledby=consent-title]", count: 0
    assert_select "form[action=?]", cookie_consent_path, count: 2
  end

  test "the banner goes once the visitor has answered" do
    scan
    sign_in_as users(:client)

    post cookie_consent_path, params: { choice: "declined" }
    get new_design_path

    assert_select "section[aria-labelledby=consent-title]", count: 0
  end

  # --- Accepting ------------------------------------------------------------------------

  test "accepting keeps the shop the visitor is looking at" do
    scan

    post cookie_consent_path, params: { choice: "accepted" }

    assert_equal "accepted", cookies[:cookie_consent]
    assert_predicate cookies[:shop_ref], :present?
    assert_predicate flash[:notice], :present?
  end

  test "the cookies expire, and are not readable by scripts" do
    scan
    post cookie_consent_path, params: { choice: "accepted" }

    set_cookie = Array(response.headers["Set-Cookie"]).flat_map { |header| header.to_s.lines }

    %w[ cookie_consent shop_ref ].each do |name|
      line = set_cookie.find { |candidate| candidate.start_with?("#{name}=") }
      assert line, "#{name} was not set"
      assert_match(/expires=/i, line, "#{name} must expire")
      assert_match(/httponly/i, line)
      assert_match(/samesite=lax/i, line)
    end
  end

  test "a returning visitor who accepted is still that shop's client" do
    scan
    post cookie_consent_path, params: { choice: "accepted" }
    close_browser
    sign_in_as users(:client)

    get new_design_path

    assert_select "body", text: /#{SHOP}/i
  end

  test "a shop scanned after accepting is kept from the first scan" do
    post cookie_consent_path, params: { choice: "accepted" }
    assert_nil cookies[:shop_ref], "no shop yet, so nothing to keep"

    scan

    assert_predicate cookies[:shop_ref], :present?
  end

  test "the same person coming back is not counted twice" do
    scan
    post cookie_consent_path, params: { choice: "accepted" }
    close_browser

    assert_no_difference -> { WorkshopLinkVisit.where(printer: @lyon).sum(:count) } do
      scan
    end
  end

  # --- Refusing and changing one's mind ---------------------------------------------------

  test "refusing sets no shop cookie, and the session still works" do
    scan

    post cookie_consent_path, params: { choice: "declined" }

    assert_equal "declined", cookies[:cookie_consent]
    assert_predicate cookies[:shop_ref], :blank?

    sign_in_as users(:client)
    get new_design_path
    assert_select "body", text: /#{SHOP}/i
  end

  test "a visitor who refused is forgotten when the browser closes" do
    scan
    post cookie_consent_path, params: { choice: "declined" }
    close_browser
    sign_in_as users(:client)

    get new_design_path

    assert_select "body", text: /#{SHOP}/i, count: 0
  end

  test "changing one's mind removes the cookie" do
    scan
    post cookie_consent_path, params: { choice: "accepted" }
    assert_predicate cookies[:shop_ref], :present?

    post cookie_consent_path, params: { choice: "declined" }

    assert_equal "declined", cookies[:cookie_consent]
    assert_predicate cookies[:shop_ref], :blank?
  end

  test "a visitor who refused is counted every visit, as before" do
    scan
    post cookie_consent_path, params: { choice: "declined" }
    close_browser

    assert_difference -> { WorkshopLinkVisit.where(printer: @lyon).sum(:count) }, 1 do
      scan
    end
  end

  # --- What is not to be trusted ----------------------------------------------------------

  test "a made-up shop cookie is ignored" do
    cookies[:cookie_consent] = "accepted"
    cookies[:shop_ref] = @lyon.id.to_s
    sign_in_as users(:client)

    get new_design_path

    assert_select "body", text: /#{SHOP}/i, count: 0
  end

  test "an unknown answer is refused and sets nothing" do
    scan

    post cookie_consent_path, params: { choice: "peut-etre" }

    assert_redirected_to cookies_path
    assert_predicate flash[:alert], :present?
    assert_nil cookies[:cookie_consent]
  end

  test "an answer in the cookie that is neither is no answer" do
    scan
    cookies[:cookie_consent] = "whatever"
    sign_in_as users(:client)

    get new_design_path

    assert_select "section[aria-labelledby=consent-title]"
  end

  test "the visitor goes back to the page they answered from" do
    scan

    post cookie_consent_path, params: { choice: "declined" }, headers: { "Referer" => new_design_url }

    assert_redirected_to new_design_url
  end

  # --- The page ---------------------------------------------------------------------------

  test "the cookies page is in the footer of every page, and says what the visitor chose" do
    get root_path
    assert_select "footer a[href=?]", cookies_path

    get cookies_path
    assert_response :success
    assert_select "body", text: /#{Regexp.escape(I18n.t('legal.cookies.choice.state.undecided'))}/

    scan
    post cookie_consent_path, params: { choice: "accepted" }
    get cookies_path

    days = Rails.application.config.tshirt.privacy[:attribution_cookie_days]
    assert_select "body", text: /#{Regexp.escape(I18n.t('legal.cookies.choice.state.accepted', days: days))}/
  end

  test "the privacy page points at the cookies page" do
    get privacy_path

    assert_select "body", text: /#{Regexp.escape(I18n.t('legal.privacy.purposes.body').last[0, 40])}/
  end

  private
    def scan(slug: @lyon.slug) = get(workshop_link_path(slug: slug), headers: BROWSER)

    # What closing the browser does: the session cookie goes, the two persistent
    # ones stay.
    def close_browser
      kept = cookies.to_hash.slice("cookie_consent", "shop_ref")
      reset!
      kept.each { |name, value| cookies[name] = value }
    end
end
