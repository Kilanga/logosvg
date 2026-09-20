# A print request has two sides: the client who sent it and the workshop that
# received it. Both read it; neither can do the other's job.
class PrintRequestPolicy < ApplicationPolicy
  def show? = client? || workshop?

  # Only a client sends, and only from a design that is theirs and finished.
  def create? = user&.client? && owns_design? && record.design&.ready?
  def new? = create?

  # The client calls it off; the workshop refuses by simply not answering.
  def cancel? = client? && record.may_cancel?

  # Both sides have a list of their own; the scope is what tells them apart.
  def index? = user&.client? || user&.printer?

  # Moving the job along is the workshop's.
  def update? = workshop? && record.open?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.nil?

      if user.printer?
        scope.where(printer_id: user.printer&.id)
      elsif user.client?
        scope.where(client: user)
      else
        scope.none
      end
    end
  end

  private
    def client? = user.present? && record.client_id == user.id

    def workshop? = user&.printer? && record.printer_id == user.printer&.id

    def owns_design? = record.design&.user_id == user&.id
end
