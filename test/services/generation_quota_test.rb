require "test_helper"

class GenerationQuotaTest < ActiveSupport::TestCase
  setup { @client = users(:client) }

  test "a client starts the day with the whole allowance" do
    assert_equal GenerationQuota.per_day, quota.remaining
    assert_equal 0, quota.used
    assert_not_predicate quota, :exceeded?
  end

  test "each attempt costs one" do
    quota.consume!

    assert_equal 1, quota.used
    assert_equal GenerationQuota.per_day - 1, quota.remaining
  end

  test "the allowance runs out and refuses the next attempt" do
    GenerationQuota.per_day.times { assert quota.consume! }

    assert_predicate quota, :exceeded?
    assert_equal 0, quota.remaining
    assert_not quota.consume!, "an exhausted allowance refuses rather than going negative"
    assert_equal GenerationQuota.per_day, quota.used
  end

  test "yesterday's attempts do not count against today" do
    GenerationCounter.create!(user: @client, day: Time.zone.yesterday, count: GenerationQuota.per_day)

    assert_equal GenerationQuota.per_day, quota.remaining
  end

  test "one client's attempts never count against another's" do
    GenerationQuota.for(users(:printer)).consume!

    assert_equal 0, quota.used
  end

  # A generation that never reached the service is our failure, not the
  # client's: the attempt is handed back.
  test "an attempt can be given back" do
    quota.consume!
    quota.refund!

    assert_equal 0, quota.used
  end

  test "giving back more than was taken never goes below zero" do
    quota.refund!
    quota.refund!

    assert_equal 0, quota.used
  end

  # Two submissions in the same instant must not both read the same count and
  # both be let through: the counter is incremented by an upsert, in one
  # statement.
  test "counting is atomic, so simultaneous attempts cannot both slip past" do
    2.times { GenerationQuota.for(@client).consume! }

    assert_equal 2, quota.used
    assert_equal 1, GenerationCounter.where(user: @client, day: Time.zone.today).count
  end

  private
    def quota = GenerationQuota.for(@client)
end
