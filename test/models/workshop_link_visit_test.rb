require "test_helper"

class WorkshopLinkVisitTest < ActiveSupport::TestCase
  setup { @printer = printers(:lyon) }

  test "each source has its own row for the day" do
    WorkshopLinkVisit.record!(@printer)
    WorkshopLinkVisit.record!(@printer, source: "qr")
    WorkshopLinkVisit.record!(@printer, source: "qr")

    assert_equal({ "link" => 1, "qr" => 2 }, WorkshopLinkVisit.where(printer: @printer).pluck(:source, :count).to_h)
  end

  test "the daily series adds every source together" do
    WorkshopLinkVisit.create!(printer: @printer, day: 2.days.ago.to_date, source: "link", count: 3)
    WorkshopLinkVisit.create!(printer: @printer, day: 2.days.ago.to_date, source: "qr", count: 4)

    assert_equal 7, WorkshopLinkVisit.series(@printer, days: 30).to_h[2.days.ago.to_date]
  end

  test "sources are counted over the window, busiest first" do
    WorkshopLinkVisit.create!(printer: @printer, day: 1.day.ago.to_date, source: "link", count: 2)
    WorkshopLinkVisit.create!(printer: @printer, day: 2.days.ago.to_date, source: "link", count: 1)
    WorkshopLinkVisit.create!(printer: @printer, day: 1.day.ago.to_date, source: "qr", count: 9)
    WorkshopLinkVisit.create!(printer: @printer, day: 40.days.ago.to_date, source: "flyer", count: 50)

    assert_equal({ "qr" => 9, "link" => 3 }, WorkshopLinkVisit.by_source(@printer, days: 30))
    assert_equal %w[ qr link ], WorkshopLinkVisit.by_source(@printer, days: 30).keys
  end

  test "another shop's visits are not counted" do
    WorkshopLinkVisit.create!(printer: printers(:rennes), day: Time.zone.today, source: "qr", count: 5)

    assert_empty WorkshopLinkVisit.by_source(@printer, days: 30)
  end
end
