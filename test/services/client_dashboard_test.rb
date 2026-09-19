require "test_helper"

# What the dashboard puts first is a business rule, not a layout choice.
class ClientDashboardTest < ActiveSupport::TestCase
  test "a failed generation is offered to be retried" do
    designs(:pending_design).fail!("le service n'a pas répondu")
    designs(:pending_design).save!

    assert_includes kinds, :design_failed
  end

  # The whole point of the platform, left undone. Both fixture designs have
  # been sent already, so one is freed first.
  test "a finished design nobody was asked to print is brought forward" do
    assert_not_includes unsent, designs(:fox_dtf), "it has a request to begin with"

    designs(:fox_dtf).print_requests.destroy_all

    assert_includes unsent, designs(:fox_dtf)
  end

  test "a design already sent to a workshop is not brought forward" do
    assert_not_includes unsent, designs(:fox_screen),
                        "that one has a print request already"
  end

  # A request that came to nothing leaves the design needing a workshop again.
  test "a design whose only request expired is brought forward again" do
    designs(:fox_dtf).print_requests.each { |r| r.expire! if r.may_expire? }

    assert_not_includes unsent, designs(:fox_dtf),
                        "an expired request is still a request on the record"
  end

  # Worth saying before the sweep expires it.
  test "a workshop that has not confirmed for two days is flagged" do
    silent = actions.select { |a| a.kind == :print_request_silent }.map(&:record)

    assert_includes silent, print_requests(:forgotten)
  end

  test "a request sent an hour ago is not yet a problem" do
    silent = actions.select { |a| a.kind == :print_request_silent }.map(&:record)

    assert_not_includes silent, print_requests(:waiting)
  end

  test "a request the workshop acknowledged is never flagged" do
    print_requests(:forgotten).acknowledge!
    print_requests(:forgotten).save!

    silent = actions.select { |a| a.kind == :print_request_silent }.map(&:record)

    assert_not_includes silent, print_requests(:forgotten)
  end

  test "the most recent thing to act on comes first" do
    dates = actions.map(&:on)

    assert_equal dates.sort.reverse, dates
  end

  # Another client's work is another client's business.
  test "nothing from another account reaches the dashboard" do
    data = ClientDashboard.call(client: users(:deleted_client))

    assert_not_includes data[:designs], designs(:fox_screen)
    assert_empty data[:actions].select { |a| a.record == print_requests(:waiting) }
  end

  test "a soft-deleted design leaves the lists entirely" do
    designs(:fox_dtf).soft_delete!

    assert_not_includes ClientDashboard.call(client: users(:client))[:designs],
                        designs(:fox_dtf)
    assert_empty actions.select { |a| a.record == designs(:fox_dtf) }
  end

  private
    def actions = ClientDashboard.call(client: users(:client))[:actions]

    def kinds = actions.map(&:kind)

    def unsent = actions.select { |a| a.kind == :design_unsent }.map(&:record)
end
