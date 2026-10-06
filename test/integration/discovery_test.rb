require "test_helper"

# What search engines and browsers ask for without being told.
class DiscoveryTest < ActionDispatch::IntegrationTest
  test "robots.txt keeps accounts out and points at the sitemap" do
    get "/robots.txt"

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_includes response.body, "Disallow: /mon-espace"
    assert_includes response.body, "Disallow: /designs"
    assert_includes response.body, "Sitemap: http://www.example.com/sitemap.xml"
  end

  test "the sitemap lists the public pages and only the listed directory entries" do
    get "/sitemap.xml"

    assert_response :success
    sitemap = Nokogiri::XML(response.body)
    locations = sitemap.xpath("//xmlns:loc").map(&:text)

    assert_includes locations, "http://www.example.com/imprimeurs"
    assert_includes locations, "http://www.example.com/mentions-legales"
    Printer.listed.each { |printer| assert_includes locations, printer_url(printer) }
    (Printer.all - Printer.listed).each { |printer| assert_not_includes locations, printer_url(printer) }
    DesignerProfile.where.not(status: "active").each do |profile|
      assert_not_includes locations, designer_url(profile)
    end
  end

  test "favicon.ico leads to the icon every layout already links" do
    get "/favicon.ico"

    assert_redirected_to "/icon.png"
    assert_response :moved_permanently
  end
end
