require "test_helper"

# An export a person can read, with the platform's vocabulary and nothing they
# did not put there.
class AccountExportTest < ActiveSupport::TestCase
  HOST = "exemple.test".freeze

  test "the account's own details are in it" do
    account = export[:account]

    assert_equal users(:client).email_address, account[:email]
    assert_equal "Claire", account[:first_name]
    assert_equal "client", account[:role]
  end

  # The point of an export: what the person made, in terms they recognise.
  test "their designs are listed with what they asked for" do
    design = export[:designs].find { |d| d[:reference] == designs(:fox_screen).token }

    assert_equal designs(:fox_screen).prompt, design[:prompt]
    assert_equal "screen_printing", design[:technique]
    assert_equal 3, design[:inks]
  end

  test "their print requests carry the consent that was recorded" do
    request = export[:print_requests].find { |r| r[:reference] == print_requests(:waiting).token }

    assert_equal "2026-09-v1", request[:consent_text_version]
    assert_not_nil request[:consented_at]
  end

  test "their reviews carry the conversation, with who said what" do
    reviews(:in_progress).messages.create!(author: users(:client), body: "Une question.")

    review = export[:reviews].find { |r| r[:reference] == reviews(:in_progress).token }

    assert_equal "moi", review[:messages].first[:author]
    assert_equal "Une question.", review[:messages].first[:body]
  end

  # The client is never handed a print file; the watermarked rendering is what
  # they may take, and the export says so by linking to that.
  test "a design links to its preview, never to the print file" do
    designs(:fox_screen).print_file.attach(
      io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml"
    )

    design = export[:designs].find { |d| d[:reference] == designs(:fox_screen).token }

    assert_match(/apercu/, design[:preview_url])
    assert_no_match(/\.svg/, design[:preview_url])
  end

  test "another account's work is not in it" do
    references = export[:designs].map { |d| d[:reference] }

    assert_not_includes references, designs(:other_client_design).token
  end

  # Only the accounts that have one.
  test "a client's export carries no shop and no designer profile" do
    assert_nil export[:printer]
    assert_nil export[:designer_profile]
  end

  test "a printer's export carries their listing" do
    data = AccountExport.call(user: users(:printer), host: HOST)

    assert_equal printers(:rennes).name, data[:printer][:name]
  end

  test "a designer's export carries their profile and levels" do
    data = AccountExport.call(user: users(:designer), host: HOST)

    assert_equal "Inès Nadeau", data[:designer_profile][:display_name]
    assert_includes data[:designer_profile][:levels], review_levels(:check).name
  end

  test "the whole thing survives being turned into JSON" do
    assert_nothing_raised { JSON.parse(JSON.generate(export)) }
  end

  private
    def export = AccountExport.call(user: users(:client), host: HOST)

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="#000"/></svg>)
    end
end
