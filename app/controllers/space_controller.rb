# Base of the four professional spaces. Authentication comes from the
# Authentication concern; this adds the role check, through a Pundit policy, on
# every action of every space controller.
class SpaceController < ApplicationController
  before_action :authorize_space

  private
    def space_key = raise NoMethodError, "#{self.class} must define #space_key"

    def authorize_space = authorize(space_key, :show?)
end
