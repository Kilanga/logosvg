class DesignPolicy < ApplicationPolicy
  # A design is private to the client who made it. Not "private unless shared":
  # there is no sharing, and the token in the URL is unguessable precisely so
  # that a leaked link is the only way anyone else could try.
  def show? = owner?

  def create? = user&.client?
  def new? = create?

  # Their own list. The scope is what narrows it; this only says who has one.
  def index? = user&.client?

  # The preview is the only rendering a client may ever download — and never
  # the print file itself.
  def image? = owner?

  # A ready design is immutable: a variant or a refinement makes a child.
  # Nothing goes further from one of several proposals until the client has
  # kept it.
  def variants? = owner? && record.ready? && !record.awaiting_choice?
  def refine? = variants?

  # Keeping one of the proposals of a click: a ready one, still on offer.
  def choose? = owner? && record.ready? && record.awaiting_choice?

  def destroy? = owner?

  class Scope < ApplicationPolicy::Scope
    def resolve = user ? scope.active.where(user: user) : scope.none
  end

  private
    def owner? = user.present? && record.user_id == user.id
end
