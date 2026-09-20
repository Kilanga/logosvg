# What a review costs and promises is the platform's decision, so the levels
# are the administration's to edit. Everyone else reads them.
class ReviewLevelPolicy < ApplicationPolicy
  def index?  = user&.admin?
  def create? = user&.admin?
  def update? = user&.admin?

  class Scope < ApplicationPolicy::Scope
    def resolve
      raise Pundit::NotAuthorizedError unless user&.admin?

      scope.all
    end
  end
end
