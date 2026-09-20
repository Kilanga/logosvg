# The blocked-terms list belongs to the administration alone: it decides what
# the platform will not draw, and nobody else has a screen for it.
class BlockedTermPolicy < ApplicationPolicy
  def index?   = user&.admin?
  def create?  = user&.admin?
  def update?  = user&.admin?
  def destroy? = user&.admin?

  class Scope < ApplicationPolicy::Scope
    def resolve
      raise Pundit::NotAuthorizedError unless user&.admin?

      scope.all
    end
  end
end
