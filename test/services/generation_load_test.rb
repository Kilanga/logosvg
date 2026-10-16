require "test_helper"

class GenerationLoadTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 16, 20, 30)
    Design.update_all(created_at: 30.days.ago, finished_at: nil)
  end

  test "counts the images drawn today, creations and reprises apart" do
    drawn(mode: "create", at: 10.minutes.ago, wait: 40)
    drawn(mode: "create", at: 9.minutes.ago, wait: 80)
    drawn(mode: "refine", at: 5.minutes.ago, wait: 120)
    drawn(mode: "variant", at: 2.hours.ago, wait: 50, status: "failed")
    drawn(mode: "upload", at: 3.minutes.ago, wait: 5)

    load = GenerationLoad.new

    assert_equal 4, load.images_today, "a dropped picture never reached the model"
    assert_equal 2, load.creations_today
    assert_equal 2, load.reprises_today
    assert_equal 1, load.failed_today
    assert_equal [ 20, 3 ], load.busiest_hour_today
    assert_equal 73, load.mean_wait_today
    assert_equal 120, load.longest_wait_today
    assert_not load.slow?
  end

  test "a wait past the threshold is slow" do
    drawn(mode: "create", at: 10.minutes.ago, wait: GenerationLoad.alert_wait_seconds + 60)

    assert GenerationLoad.new.slow?
  end

  test "the last seven days, quiet ones included, on the local calendar" do
    drawn(mode: "create", at: Time.zone.local(2026, 10, 16, 0, 30))
    drawn(mode: "create", at: 2.days.ago)
    drawn(mode: "create", at: 2.days.ago)
    drawn(mode: "create", at: 8.days.ago)

    week = GenerationLoad.new.last_week

    assert_equal 7, week.size
    assert_equal Date.new(2026, 10, 10), week.first.date
    assert_equal [ 0, 0, 0, 0, 2, 0, 1 ], week.map(&:images)
  end

  test "a quiet day says nothing" do
    load = GenerationLoad.new

    assert_equal 0, load.images_today
    assert_nil load.busiest_hour_today
    assert_nil load.mean_wait_today
    assert_not load.slow?
  end

  test "a design records when it came back, ready or failed" do
    design = designs(:pending_design)
    design.update_columns(status: "generating")

    design.succeed!
    assert_equal Time.current, design.reload.finished_at

    design.update_columns(status: "generating", finished_at: nil)
    design.fail!("plus de place")
    assert_equal Time.current, design.reload.finished_at
  end

  private
    def drawn(mode:, at:, wait: nil, status: "ready")
      design = designs(:fox_screen).dup
      design.assign_attributes(token: SecureRandom.base58(24), mode: mode, status: status,
                               created_at: at, finished_at: wait && at + wait.seconds, parent_id: nil, root_id: nil)
      design.save!(validate: false)
    end
end
