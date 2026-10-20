# A retouch or a batch of variants asked of a design: every check made before
# the generation service is called, and the call itself. Moved out of
# Client::DesignsController (revue du 16/10/2026), where it was sixty lines of
# one private method.
#
# A reprise does not count against the client's creations of the day (decided
# on 16/10/2026): the three reprises of a design already bound it, and a client
# who retouched once found « 2 créations » left after two. The load it puts on
# the generation machine is followed on the admin dashboard instead
# (GenerationLoad). The shop's monthly allowance counts print requests, not
# generations, since 20/10/2026: a reprise spends nothing of it.
#
# `request` is the call to the service — a refinement or variants — run once,
# and once more after the design has been revived if the service had
# forgotten it.
class TakeDesignFurther
  Result = Data.define(:design, :error) do
    def success? = error.nil?
  end

  def self.call(...) = new(...).call

  def initialize(design:, user:, instruction: nil, &request)
    @design = design
    @user = user
    @instruction = instruction
    @request = request
  end

  def call
    refusal = refusal_before_spending
    return failure(refusal) if refusal

    begin
      children = CreateDesignChildren.call(parent: @design, instruction: @instruction) do
        @request.call
      rescue GeneratorClient::NotFound
        ReviveDesign.call(@design)
        @request.call
      end
    rescue ReviveDesign::Unrecoverable
      return failure(t("client.designs.take_it_further.too_old"))
    rescue GeneratorClient::BudgetExhausted
      return failure(t("client.designs.take_it_further.budget_exhausted"))
    rescue GeneratorClient::Rejected => e
      return failure(e.detail)
    rescue GeneratorClient::Error
      return failure(t("designs.errors.unavailable"))
    end

    # Retouched or varied straight from the choice screen: the proposal it
    # started from is the one kept.
    ChooseProposal.call(@design) if @design.awaiting_choice?
    Result.new(design: children.first, error: nil)
  end

  private
    def t(...) = I18n.t(...)

    def failure(message) = Result.new(design: nil, error: message)

    # The client's own words are read first, then whether this shop still
    # pays for their reprises, then whether any are left: nothing is spent
    # before all three hold.
    def refusal_before_spending
      if @instruction.present? && (term = BlockedTerm.matching(@instruction))
        BlockedTerm.record_hit!(term)
        return t("client.designs.take_it_further.blocked")
      end

      # Every reprise counts against the shop the design was made for. Once
      # the client has left that shop — or it has let them go — it no longer
      # pays for their reprises: a new design, with the new shop, does.
      return t("client.designs.take_it_further.other_workshop") unless reprise_allowed?
      return t("client.designs.take_it_further.budget_exhausted") if @design.refinements_remaining.zero?

      nil
    end

    def reprise_allowed?
      @user.attached_to_workshop? &&
        (@design.printer_id.nil? || @design.printer_id == @user.active_workshop_id)
    end
end
