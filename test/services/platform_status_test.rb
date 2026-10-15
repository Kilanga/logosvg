require "test_helper"

# E2, reported on 15/10/2026: « 756 tâches en échec » and « À surveiller »,
# with nothing to start from.
class PlatformStatusTest < ActiveSupport::TestCase
  test "a failed job is named by its error, not only counted" do
    error = { exception_class: "Net::ReadTimeout", message: "Net::ReadTimeout with #<TCPSocket>",
              backtrace: [ "x.rb:1" ] }.to_json

    label = PlatformStatus.new.send(:failure_label, error)

    assert_equal "Net::ReadTimeout: Net::ReadTimeout with #<TCPSocket>", label
  end

  test "an unreadable error is shown as it is" do
    assert_equal "boom", PlatformStatus.new.send(:failure_label, "boom")
  end

  test "a cold catalogue says why it is to watch" do
    check = PlatformStatus.new.send(:catalogue)

    assert_predicate check, :warning?
    assert_includes check.detail, I18n.t("admin.status.catalogue_cold")
  end
end
