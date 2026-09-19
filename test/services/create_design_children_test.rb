require "test_helper"

class CreateDesignChildrenTest < ActiveSupport::TestCase
  setup { @parent = designs(:fox_screen) }

  test "a batch of variants makes one child per job the service opened" do
    children = CreateDesignChildren.call(parent: @parent) { variants_answer }

    assert_equal 3, children.size
    assert_equal %w[ job-a job-b job-c ], children.map(&:generator_job_id)
    assert(children.all? { |child| child.mode == "variant" })
    assert(children.all?(&:generating?), "a child exists because the service accepted it")
  end

  test "a refinement makes a single child, and keeps the instruction that asked for it" do
    children = CreateDesignChildren.call(parent: @parent, instruction: "un casque rouge") do
      { "job_id" => "job-d", "refinements_left" => 2 }
    end

    assert_equal 1, children.size
    assert_equal "refine", children.first.mode
    assert_equal "un casque rouge", children.first.instruction
  end

  # The technique shaped the prompt, not only the output file: a child of a
  # screen-printing design is a screen-printing design.
  test "a child inherits what was asked of the parent" do
    child = CreateDesignChildren.call(parent: @parent) { { "job_id" => "job-e" } }.first

    assert_equal @parent.prompt, child.prompt
    assert_equal @parent.technique, child.technique
    assert_equal @parent.style, child.style
    assert_equal @parent.colors_requested, child.colors_requested
    assert_equal @parent.print_width_cm, child.print_width_cm
    assert_equal @parent.user, child.user
    assert_equal @parent.printer, child.printer
  end

  # One lineage, one root: a client may go back to any version and start again
  # from there without the tree coming apart.
  test "the whole lineage hangs off the first design, not off each parent" do
    child = CreateDesignChildren.call(parent: @parent) { { "job_id" => "job-f" } }.first
    grandchild = CreateDesignChildren.call(parent: child) { { "job_id" => "job-g" } }.first

    assert_equal @parent, child.root
    assert_equal @parent, grandchild.root, "the root is the head of the lineage, not the parent"
    assert_equal child, grandchild.parent
  end

  test "the refinement budget is the service's figure, carried as it came" do
    child = CreateDesignChildren.call(parent: @parent) do
      { "job_id" => "job-h", "refinements_left" => 0 }
    end.first

    assert_equal 0, child.refinements_left
  end

  test "each child gets its own polling job" do
    assert_enqueued_jobs 3, only: PollDesignJob do
      CreateDesignChildren.call(parent: @parent) { variants_answer }
    end
  end

  # Three children from one call: either the lineage records all of them or the
  # client is not shown a design the service has no job for.
  test "nothing is recorded when one child cannot be saved" do
    @parent.update_column(:prompt, "ab")

    assert_no_difference "Design.count" do
      assert_raises(ActiveRecord::RecordInvalid) do
        CreateDesignChildren.call(parent: @parent) { variants_answer }
      end
    end
  end

  private
    def variants_answer
      { "job_ids" => %w[ job-a job-b job-c ], "job_id" => "job-a", "refinements_left" => 2 }
    end
end
