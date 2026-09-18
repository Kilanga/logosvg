class UserPolicy < ApplicationPolicy
  # Signing up is for visitors. Someone already signed in has no business
  # creating a second account from the form.
  def create? = user.nil?
  def new? = create?
end
