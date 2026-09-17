require "test_helper"

# Guards the choices the whole application rests on. They are cheap to break by
# accident and expensive to notice late.
class ApplicationConfigurationTest < ActiveSupport::TestCase
  test "the interface speaks French on Paris time" do
    assert_equal :fr, I18n.default_locale
    assert_equal [ :fr ], I18n.available_locales
    assert_equal "Europe/Paris", Time.zone.name
  end

  test "dates and amounts are formatted the French way" do
    assert_equal "14/10/2026", I18n.l(Date.new(2026, 10, 14))
    assert_equal "1 234,50 €", ActiveSupport::NumberHelper.number_to_currency(1234.5)
  end

  test "business settings come from config/settings.yml" do
    settings = Rails.application.config.tshirt

    assert settings.platform_name.present?
    assert_equal 5, settings.generation[:quota_per_day]
  end

  # Every value listed under "Décisions ouvertes" in docs/SPEC.md must exist in
  # configuration. A missing key here means a provisional value was written
  # straight into the code instead.
  test "each open decision has a configured placeholder" do
    settings = Rails.application.config.tshirt

    assert_not_nil settings.platform_name
    assert_not_nil settings.reviews[:platform_fee_rate]
    assert_not_nil settings.reviews[:auto_accept_days]
    assert_not_nil settings.reviews[:proposal_expiry_hours]
    assert_not_nil settings.reviews[:designer_claim_timeout_hours]
    assert_not_nil settings.reviews[:return_rate_alert_threshold]
    assert_not_nil settings.print_requests[:expire_after_days]
    assert_not_nil settings.print_requests[:reminder_after_hours]
    assert_not_nil settings.subscriptions[:past_due_grace_days]
    assert_not_nil settings.privacy[:design_retention_days]
    assert_not_nil settings.privacy[:print_request_anonymize_days]
    assert_not_nil settings.privacy[:consent_text_version]
  end

  test "the client may never download the vectorised SVG" do
    assert_not Rails.application.config.tshirt.uploads[:client_may_download_svg]
  end

  test "self-hosted typefaces resolve through the asset pipeline" do
    load_path = Rails.application.assets.load_path

    %w[Figtree.woff2 BarlowCondensed-600.woff2 BarlowCondensed-700.woff2].each do |file|
      assert load_path.find(file), "#{file} is missing from the asset load path"
    end
  end

  test "the compiled stylesheet carries the visual tokens and the screen tint" do
    asset = Rails.application.assets.load_path.find("tailwind.css")
    assert asset, "tailwind.css has not been built"

    css = Rails.application.assets.compilers.compile(asset)
    font_urls = css.scan(%r{url\("?([^")]+\.woff2)"?\)}).flatten

    # Asserted on booleans rather than on the stylesheet itself: a failure here
    # should name what is missing, not print the whole build.
    assert css.include?("#1f5f7a"), "the emulsion token is missing from the build"
    assert css.include?("repeating-linear-gradient"), "the screen tint is missing from the build"
    assert font_urls.any? { |url| url.match?(%r{\A/assets/Figtree-\w+\.woff2\z}) },
           "Figtree is not served with a digest. Font URLs found: #{font_urls.inspect}"
  end
end
