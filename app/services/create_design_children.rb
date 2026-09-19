# Turns a refinement or a variants request into designs of the same lineage.
#
# A ready design never changes: taking it further makes children. They inherit
# the technique — it shaped the prompt, not only the file — and the whole
# lineage hangs off one root, so a client can go back to any version and start
# again from there.
class CreateDesignChildren
  def self.call(parent:, instruction: nil, &request) = new(parent: parent, instruction: instruction).call(&request)

  def initialize(parent:, instruction: nil)
    @parent = parent
    @instruction = instruction.presence
  end

  # The block performs the call to the service: the caller owns the error
  # handling, because a refused refinement and a refused variant are told to
  # the client differently.
  def call
    answer = yield
    job_ids = Array(answer["job_ids"].presence || answer["job_id"])

    children = job_ids.map { |job_id| build_child(job_id, answer) }
    Design.transaction { children.each(&:save!) }

    children.each { |child| PollDesignJob.perform_later(child) }
    children
  end

  private
    def build_child(job_id, answer)
      Design.new(
        user: @parent.user,
        printer: @parent.printer,
        parent: @parent,
        root: @parent.lineage_root,
        mode: @instruction ? "refine" : "variant",
        instruction: @instruction,
        # Inherited wholesale: a child of a screen-printing design is a
        # screen-printing design, whatever else changes.
        prompt: @parent.prompt,
        style: @parent.style,
        technique: @parent.technique,
        colors_requested: @parent.colors_requested,
        print_width_cm: @parent.print_width_cm,
        remove_background: @parent.remove_background,
        generator_job_id: job_id,
        refinements_left: answer["refinements_left"],
        status: "generating"
      )
    end
end
