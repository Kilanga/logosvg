require "test_helper"

class BlockedTermTest < ActiveSupport::TestCase
  setup { BlockedTerm.reset_cache! }

  test "a term is folded on the way in, so one spelling is one row" do
    term = BlockedTerm.create!(term: "  Adidas  ")

    assert_equal "adidas", term.term
  end

  test "the same term twice is refused whatever the case" do
    assert_not BlockedTerm.new(term: "NIKEE").valid?
  end

  test "a prompt containing an active term is caught" do
    assert_equal "nikee", BlockedTerm.matching("un logo nikee sur fond noir")
  end

  test "the match is case-insensitive" do
    assert_equal "mickey", BlockedTerm.matching("Un MICKEY qui danse")
  end

  # A list that refuses innocent prompts is one the administration will be
  # asked to remove.
  test "a term is matched as a whole word, never as a fragment" do
    assert_nil BlockedTerm.matching("un jeu de cartes vintage"), "'art' must not catch 'cartes'"
    assert_equal "art", BlockedTerm.matching("une affiche art déco")
  end

  test "a deactivated term catches nothing" do
    assert_nil BlockedTerm.matching("un design obsolete")
  end

  test "a prompt with nothing to catch passes" do
    assert_nil BlockedTerm.matching("un renard qui fait du skate")
  end

  # How often a term catches something is what tells an administrator whether
  # it earns its place.
  test "a hit is counted and dated" do
    BlockedTerm.record_hit!("mickey")

    term = blocked_terms(:personnage).reload

    assert_equal 4, term.hits_count
    assert_not_nil term.last_hit_at
  end

  test "changing the list clears the cache at once" do
    assert_nil BlockedTerm.matching("un ballon adidas")

    BlockedTerm.create!(term: "adidas")

    assert_equal "adidas", BlockedTerm.matching("un ballon adidas")
  end

  test "deactivating a term takes it out of circulation at once" do
    blocked_terms(:personnage).update!(active: false)

    assert_nil BlockedTerm.matching("un mickey qui danse")
  end
end

# Refused on this side, so it costs no allowance and reaches no other machine.
class DesignBlockedTermTest < ActiveSupport::TestCase
  setup { BlockedTerm.reset_cache! }

  test "a design whose prompt carries a blocked term is refused" do
    design = build_design(prompt: "un logo nikee sur un t-shirt")

    assert_not design.valid?
    assert design.errors.include?(:prompt)
  end

  test "the refusal names the term, so the client can fix it" do
    design = build_design(prompt: "un logo nikee")
    design.valid?

    assert_match(/nikee/, design.errors.full_messages_for(:prompt).first)
  end

  test "an innocent prompt passes" do
    assert_predicate build_design(prompt: "un renard qui fait du skate"), :valid?
  end

  # Checked at creation only: an old design must not become unsavable because
  # the list grew afterwards.
  test "a term added later does not freeze designs already made" do
    design = designs(:fox_screen)
    BlockedTerm.create!(term: "renard")

    assert_predicate design.reload, :valid?
  end

  private
    def build_design(**attributes)
      Design.new({
        user: users(:client), technique: "screen_printing", print_width_cm: 25
      }.merge(attributes))
    end
end
