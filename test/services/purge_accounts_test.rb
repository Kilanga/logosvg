require "test_helper"

# 10/10/2026: the production database held only demonstration and test
# accounts. Everything accounts made goes; what the platform itself set stays.
class PurgeAccountsTest < ActiveSupport::TestCase
  test "without confirmation, nothing is deleted" do
    assert_no_difference -> { User.count } do
      PurgeAccounts.call(confirm: false, io: StringIO.new)
    end
  end

  test "every account and what it made goes; levels and blocked terms stay" do
    BlockedTerm.create!(term: "terme-test", created_by_id: users(:admin).id)
    levels = ReviewLevel.count
    terms = BlockedTerm.count
    assert_operator User.count, :>, 0
    assert_operator Printer.count, :>, 0

    PurgeAccounts.call(confirm: true, io: StringIO.new)

    PurgeAccounts::TABLES.each do |table|
      assert_equal 0, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{table}").to_i, table
    end
    assert_equal levels, ReviewLevel.count
    assert_equal terms, BlockedTerm.count
    assert_nil BlockedTerm.find_by(term: "terme-test").created_by_id
  end

  test "the files attached to accounts' records go with them" do
    printer = printers(:rennes)
    printer.logo.attach(io: StringIO.new("png"), filename: "logo.png", content_type: "image/png")

    assert_difference -> { ActiveStorage::Blob.count }, -1 do
      PurgeAccounts.call(confirm: true, io: StringIO.new)
    end
    assert_equal 0, ActiveStorage::Attachment.where(record_type: "Printer").count
  end
end
