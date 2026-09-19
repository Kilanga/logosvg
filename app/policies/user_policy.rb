class UserPolicy < ApplicationPolicy
  # Signing up is for visitors. Someone already signed in has no business
  # creating a second account from the form.
  def create? = user.nil?
  def new? = create?

  # An account is edited by the person whose account it is, and by nobody else
  # — not even an administrator, who has no screen for it.
  def update? = user.present? && user.id == record.id
  def edit? = update?
end
