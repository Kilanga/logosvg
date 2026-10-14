class DesignPolicy < ApplicationPolicy
  # A design is private to the client who made it. Not "private unless shared":
  # there is no sharing, and the token in the URL is unguessable precisely so
  # that a leaked link is the only way anyone else could try.
  def show? = owner?

  # A client creates only once a workshop has them. See docs/SPEC.md,
  # "Rattachement d'un client à un atelier".
  def create? = user&.client? && user.attached_to_workshop?
  def new? = create?

  # Their own list. The scope is what narrows it; this only says who has one.
  def index? = user&.client?

  # The preview is the only rendering a client may ever download — and never
  # the print file itself.
  #
  # The others who work on the design see it too (reported on 14/10/2026: the
  # workshop's print requests showed a broken image): the workshop it was sent
  # to, the designers who may take or have taken its review, and the
  # administration. Each through its own scope, so the rule is the one that
  # already says which requests and reviews they can open.
  def image? = owner? || user&.admin? || received_by_workshop? || reviewed_by_designer?

  # A ready design is immutable: a variant or a refinement makes a child.
  # Asked of one of several proposals, it keeps that one (see the controller):
  # the client picks and retouches on the same screen.
  # A client's own image put in format is kept as it is: nothing to redraw.
  def variants? = owner? && record.ready? && !record.upload?
  def refine? = variants?

  # Saying yes to what the workshop will print, once the file is ready. Only a
  # client's own picture asks for it, and only once.
  def approve_print? = owner? && record.ready? && record.print_approval_required? && record.print_approved_at.nil?

  # The same picture put in format for another technique: a new upload, free
  # like the first, from the image already sent. Not before the first one is
  # done — it is by seeing the result that one wants another.
  def reconvert? = owner? && record.upload? && (record.ready? || record.failed?) && record.reference_image.attached?

  # Keeping one of the proposals of a click: a ready one, still on offer.
  def choose? = owner? && record.ready? && record.awaiting_choice?

  def destroy? = owner?

  class Scope < ApplicationPolicy::Scope
    def resolve = user ? scope.active.where(user: user) : scope.none
  end

  private
    def owner? = user.present? && record.user_id == user.id

    def received_by_workshop?
      user&.printer? &&
        PrintRequestPolicy::Scope.new(user, PrintRequest).resolve.where(design_id: record.id).exists?
    end

    def reviewed_by_designer?
      user&.designer? &&
        ReviewPolicy::Scope.new(user, Review).resolve.where(design_id: record.id).exists?
    end
end
