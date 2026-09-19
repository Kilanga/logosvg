require "test_helper"

# The state machine, transition by transition — including the ones that must
# not happen. See docs/SPEC.md, "Machines à états".
class DesignStateMachineTest < ActiveSupport::TestCase
  test "a new design starts pending" do
    assert_predicate build_design, :pending?
  end

  test "pending starts generating" do
    design = build_design

    assert design.may_start?
    design.start!

    assert_predicate design, :generating?
  end

  test "generating succeeds into ready" do
    design = generating

    assert design.may_succeed?
    design.succeed!

    assert_predicate design, :ready?
  end

  test "generating fails, and keeps the reason" do
    design = generating

    assert design.may_fail?
    design.fail!("le service n'a pas répondu")

    assert_predicate design, :failed?
    assert_equal "le service n'a pas répondu", design.error_message
  end

  test "pending can fail without ever reaching the service" do
    design = build_design

    assert design.may_fail?
    design.fail!("quota dépassé")

    assert_predicate design, :failed?
  end

  # The point of the failed state: a client retries without being charged an
  # attempt, because a failure never consumed one.
  test "failed starts again" do
    design = generating.tap { |d| d.fail!("réseau") }

    assert design.may_start?
    design.start!

    assert_predicate design, :generating?
  end

  test "pending cannot succeed: nothing has been generated yet" do
    design = build_design

    assert_not design.may_succeed?
    assert_raises(AASM::InvalidTransition) { design.succeed! }
  end

  test "ready never moves again: a ready design is immutable" do
    design = generating.tap(&:succeed!)

    assert_not design.may_start?
    assert_not design.may_succeed?
    assert_not design.may_fail?

    assert_raises(AASM::InvalidTransition) { design.start! }
    assert_raises(AASM::InvalidTransition) { design.succeed! }
    assert_raises(AASM::InvalidTransition) { design.fail!("trop tard") }
  end

  test "failed cannot succeed without being started again" do
    design = generating.tap { |d| d.fail!("réseau") }

    assert_not design.may_succeed?
    assert_raises(AASM::InvalidTransition) { design.succeed! }
  end

  test "generating cannot start a second time" do
    design = generating

    assert_not design.may_start?
    assert_raises(AASM::InvalidTransition) { design.start! }
  end

  private
    def build_design(**attributes)
      Design.create!({
        user: users(:client),
        prompt: "un renard qui fait du skate",
        technique: "screen_printing",
        colors_requested: 3,
        print_width_cm: 25
      }.merge(attributes))
    end

    def generating = build_design.tap(&:start!)
end

class DesignTest < ActiveSupport::TestCase
  test "a design needs a prompt the service will accept" do
    assert_not valid_design(prompt: "ok").valid?
    assert_not valid_design(prompt: "a" * 301).valid?
  end

  # It is asked of the client now, for every technique — a design with no size
  # is one no workshop can be matched against.
  test "a design needs a print size, whatever its technique" do
    %w[ screen_printing dtf ].each do |technique|
      design = valid_design(technique: technique, print_width_cm: nil)

      assert_not design.valid?, "#{technique} must still be given a width"
      assert design.errors.include?(:print_width_cm)
    end
  end

  test "a print size outside what a garment takes is refused" do
    assert_not valid_design(print_width_cm: 2).valid?
    assert_not valid_design(print_width_cm: 61).valid?
    assert_predicate valid_design(print_width_cm: 3), :valid?
    assert_predicate valid_design(print_width_cm: 60), :valid?
  end

  test "a design needs a technique the catalogue knows" do
    design = Design.new(user: users(:client), prompt: "un renard", technique: "lithographie")

    assert_not design.valid?
    assert design.errors.include?(:technique)
  end

  # The technique shaped the prompt, not only the output file: changing it
  # afterwards would describe a design nobody generated.
  test "the technique is frozen once the design exists" do
    design = designs(:fox_screen)
    design.technique = "dtf"

    assert_not design.valid?
    assert design.errors.include?(:technique)
  end

  test "public urls carry the token, never the id" do
    assert_equal designs(:fox_screen).token, designs(:fox_screen).to_param
    assert_not_equal designs(:fox_screen).id.to_s, designs(:fox_screen).to_param
  end

  test "a token is assigned without being asked for" do
    design = valid_design(technique: "dtf").tap(&:save!)

    assert design.token.present?
  end

  test "vector and raster designs are told apart by their print format" do
    assert_predicate designs(:fox_screen), :vector?
    assert_predicate designs(:fox_dtf), :raster?
  end

  test "a design with no file yet falls back to the technique's family" do
    design = Design.new(technique: "dtf")

    assert_predicate design, :raster?
  end

  test "soft delete keeps the record out of the client's lists" do
    design = designs(:fox_screen)
    design.soft_delete!

    assert_not_predicate design, :active?
    assert_not_includes Design.active, design
  end

  test "compatibility is asked of the shop, with this design's own figures" do
    result = designs(:fox_screen).compatibility_with(printers(:rennes))

    assert_predicate result, :compatible?

    assert_not_predicate designs(:fox_dtf).compatibility_with(printers(:rennes)), :compatible?
  end

  # A design too wide for a shop's press is a design that shop cannot print,
  # whatever else matches.
  test "a design wider than the press is refused by that shop" do
    wide = designs(:fox_screen).tap { |d| d.update!(print_width_cm: 40) }

    result = wide.compatibility_with(printers(:rennes))

    assert_not_predicate result, :compatible?
    assert_equal :too_wide, result.reason
  end

  private
    def valid_design(**attributes)
      Design.new({
        user: users(:client),
        prompt: "un renard qui fait du skate",
        technique: "screen_printing",
        print_width_cm: 25
      }.merge(attributes))
    end
end
