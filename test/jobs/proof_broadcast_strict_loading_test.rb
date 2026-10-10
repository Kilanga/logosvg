require "test_helper"

# The proof is part of the design panel, and the panel is pushed from the job
# that brings the file home — a bare `Design.find`, nothing preloaded. With the
# development setting on, any lazy jump in the proof would raise there, just
# as the client's screen waits for the result.
class ProofBroadcastStrictLoadingTest < ActiveSupport::TestCase
  setup do
    design = Design.new(user: users(:client), printer: printers(:rennes), mode: "upload", prompt: "Logo du club",
                        technique: "screen_printing", colors_requested: 2, print_width_cm: 25,
                        reference_rights_confirmed: true)
    design.reference_image.attach(io: StringIO.new("not read"), filename: "image.png", content_type: "image/png")
    design.save!
    design.update_columns(status: "ready", print_format: "svg", inks_count: 2)
    @id = design.id

    @previous = ActiveRecord::Base.strict_loading_by_default
    ActiveRecord::Base.strict_loading_by_default = true
  end

  teardown { ActiveRecord::Base.strict_loading_by_default = @previous }

  test "a ready upload, proof included, is broadcast with strict loading on" do
    assert_nothing_raised { DesignChannel.broadcast(Design.find(@id)) }
  end
end
