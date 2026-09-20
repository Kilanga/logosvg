require "test_helper"

# The completion criterion of step 7 lives here: "un graphiste sans versements
# activés ne peut rien prendre".
class DesignerAvailabilityTest < ActiveSupport::TestCase
  test "a vetted, payable designer who is accepting work can take it" do
    assert_predicate designer_profiles(:ines), :can_take_work?
    assert_nil designer_profiles(:ines).unavailable_reason
  end

  # The rule the whole step exists for.
  test "a designer Stripe cannot pay takes nothing, however complete the rest" do
    leo = designer_profiles(:leo)

    assert_predicate leo, :active?
    assert leo.accepting_work?
    assert_not_predicate leo, :can_take_work?
    assert_equal :payouts_disabled, leo.unavailable_reason
  end

  test "an unvetted designer takes nothing, even with payouts on" do
    nour = designer_profiles(:nour)

    assert nour.payouts_enabled?
    assert_not_predicate nour, :can_take_work?
    assert_equal :pending_review, nour.unavailable_reason
  end

  test "a suspended designer takes nothing" do
    assert_not_predicate designer_profiles(:suspendu), :can_take_work?
    assert_equal :suspended, designer_profiles(:suspendu).unavailable_reason
  end

  # Away for a fortnight is not the same as unvetted or unpaid, and the
  # sentence shown has to say which.
  test "a designer who stepped away takes nothing, and says so differently" do
    tom = designer_profiles(:tom)

    assert_not_predicate tom, :can_take_work?
    assert_equal :not_accepting, tom.unavailable_reason
  end

  test "losing payouts takes an active designer out of circulation at once" do
    ines = designer_profiles(:ines)
    ines.update!(payouts_enabled: false)

    assert_not_predicate ines, :can_take_work?
  end

  # The scope the assignment rule will use at step 8.
  test "the accepting scope holds to designers who can actually be paid" do
    accepting = DesignerProfile.listed.accepting

    assert_includes accepting, designer_profiles(:ines)
    assert_not_includes accepting, designer_profiles(:leo), "cannot be paid"
    assert_not_includes accepting, designer_profiles(:tom), "not accepting"
    assert_not_includes accepting, designer_profiles(:nour), "not vetted"
  end
end

class DesignerProfileTest < ActiveSupport::TestCase
  test "the public list holds to active profiles" do
    listed = DesignerProfile.listed

    assert_includes listed, designer_profiles(:ines)
    assert_not_includes listed, designer_profiles(:nour)
    assert_not_includes listed, designer_profiles(:suspendu)
  end

  test "a profile needs a name to show" do
    assert_not build_profile(display_name: "").valid?
  end

  # A designer writing their page over three sittings must be able to save it
  # half-finished; the completeness checks belong to activation.
  test "an incomplete profile saves, but cannot be activated" do
    profile = designer_profiles(:ines)
    profile.update!(bio: "")

    assert_predicate profile.reload, :persisted?
    assert_not_predicate profile, :ready_for_activation?
  end

  test "activation needs a bio, a city and at least one level" do
    profile = designer_profiles(:ines)

    assert_predicate profile, :ready_for_activation?

    profile.review_levels = []

    assert_not_predicate profile, :ready_for_activation?
    assert profile.errors.include?(:review_levels)
  end

  test "a level a designer did not accept is not one they offer" do
    assert designer_profiles(:tom).accepts?(review_levels(:check))
    assert_not designer_profiles(:tom).accepts?(review_levels(:custom))
  end

  test "the offering scope finds the designers who take a given level" do
    offering_custom = DesignerProfile.offering(review_levels(:custom))

    assert_includes offering_custom, designer_profiles(:ines)
    assert_not_includes offering_custom, designer_profiles(:tom)
  end

  # Specialties and languages are closed lists: a value nobody can filter on
  # would simply never be found.
  test "a specialty nobody can filter on is refused" do
    assert_not build_profile(specialties: %w[ macrame ]).valid?
    assert_predicate build_profile(specialties: %w[ lettering ]), :valid?
  end

  test "changing the city sends the profile back to the map" do
    assert_enqueued_with job: GeocodeDesignerProfileJob do
      designer_profiles(:ines).update!(city: "Saint-Étienne")
    end
  end

  test "an edit that leaves the city alone does not" do
    assert_no_enqueued_jobs only: GeocodeDesignerProfileJob do
      designer_profiles(:ines).update!(bio: "Une autre présentation, assez longue pour passer.")
    end
  end

  private
    def build_profile(**attributes)
      DesignerProfile.new({
        user: users(:designer_blank),
        display_name: "Sasha Morel"
      }.merge(attributes))
    end
end

class ReviewLevelTest < ActiveSupport::TestCase
  test "the offered levels come in the order a client reads them" do
    assert_equal %w[ check retouch custom ], ReviewLevel.offered.map(&:key)
  end

  # A level with no price is quoted case by case. That is a rule, not a gap.
  test "only the custom level may have no price" do
    assert_predicate review_levels(:custom), :quoted?
    assert_nil review_levels(:custom).price_cents

    priced = review_levels(:check)
    priced.price_cents = nil

    assert_not priced.valid?
  end

  # Rounded down so the designer never loses a centime to rounding.
  test "the platform's share is rounded in the designer's favour" do
    level = review_levels(:check)
    level.update!(price_cents: 1999)

    assert_equal 399, level.platform_fee_cents, "20% of 1999 is 399.8"
    assert_equal 1600, level.designer_share_cents
    assert_equal 1999, level.platform_fee_cents + level.designer_share_cents
  end

  test "a quoted level has no share to compute until a price is agreed" do
    assert_equal 0, review_levels(:custom).platform_fee_cents
    assert_equal 780, review_levels(:custom).platform_fee_cents(3900)
  end
end
