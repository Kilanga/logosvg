class DesignerProfilePolicy < ApplicationPolicy
  # A profile is public once it is active. Its owner sees it before that, which
  # is what previewing their own page means.
  def show? = record.active? || owner? || user&.admin?

  def index? = true

  def edit?   = owner?
  def update? = owner?

  # Onboarding is the designer's own; nobody does it for them.
  def onboard? = owner?

  # Approving and suspending belong to the administration alone.
  def approve? = user&.admin?
  def suspend? = approve?

  class Scope < ApplicationPolicy::Scope
    # The public list, for everyone alike. An administrator reviewing profiles
    # does it from /admin, not by browsing with extra powers.
    def resolve = scope.listed
  end

  class AdminScope < ApplicationPolicy::Scope
    def resolve
      raise Pundit::NotAuthorizedError unless user&.admin?

      scope.all
    end
  end

  private
    def owner? = user.present? && record.user_id == user.id
end
