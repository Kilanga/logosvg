# Guards the four professional spaces. Each subclass names the single role that
# may enter, so "an administrator never uses another role's space" is enforced
# rather than merely intended. See docs/SPEC.md, "Rôles et parcours".
class SpacePolicy
  attr_reader :user, :space

  def self.role = raise NoMethodError, "#{name} must define .role"

  def initialize(user, space)
    @user = user
    @space = space
  end

  def show? = user.present? && user.active? && user.role == self.class.role
end
