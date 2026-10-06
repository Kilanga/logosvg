# The client keeps one of the proposals a click drew.
#
# The others are set aside — soft-deleted, like any design the client throws
# away — so the lineage carries on from a single image. They still count: the
# click that drew them was a generation and a reprise whichever one was kept.
class ChooseProposal
  def self.call(design) = new(design).call

  def initialize(design)
    @design = design
  end

  def call
    Design.transaction do
      @design.update!(chosen_at: Time.current)
      Design.active.where(batch_token: @design.batch_token).where.not(id: @design.id)
            .update_all(deleted_at: Time.current, updated_at: Time.current)
    end
    @design
  end
end
