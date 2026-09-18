class PrinterPolicy < ApplicationPolicy
  # A listing is public once it is listed. Its owner sees it before that, which
  # is what "aperçu public" on the edit screen means.
  def show? = record.listed? || owner?

  def edit?   = owner?
  def update? = owner?

  # Only from a draft, and only once the listing says enough to be judged.
  def submit? = owner? && record.draft?

  # Publishing and suspending belong to the administration alone.
  def publish? = user&.admin?
  def suspend? = publish?

  class Scope < ApplicationPolicy::Scope
    # The directory is the public directory, for everyone. An administrator
    # reviewing listings does it from /admin, not by browsing with extra
    # powers — see docs/SPEC.md, "l'admin n'utilise pas les espaces des autres
    # rôles".
    def resolve = scope.listed
  end

  # What the administration reviews: everything, ordered by what is waiting.
  class AdminScope < ApplicationPolicy::Scope
    def resolve
      raise Pundit::NotAuthorizedError unless user&.admin?

      scope.all
    end
  end

  private
    def owner? = user.present? && record.user_id == user.id
end
