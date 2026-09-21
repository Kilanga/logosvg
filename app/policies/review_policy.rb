# A review has two sides and an onlooker: the client who paid, the designer who
# does the work, and an administrator settling a dispute.
class ReviewPolicy < ApplicationPolicy
  def show? = client? || designer? || user&.admin?

  # Each of the three has a list of their own; the scope is what tells them
  # apart. The administration's is a different scope, not a different rule.
  def index? = user&.client? || user&.designer? || user&.admin?

  # Only a client buys one, and only for a finished design of their own.
  def create? = user&.client? && owns_design? && record.design&.ready?
  def new? = create?

  # --- The client's own actions ---------------------------------------------

  def accept? = client? && record.may_accept?

  def revision? = client? && record.may_request_revision?

  def accept_proposal? = client? && record.may_accept_proposal?

  def decline_proposal? = client? && record.may_decline_proposal?

  # Only offered once the chosen designer has gone quiet.
  def reopen? = client? && record.chosen_designer_silent?

  # Rated once, after it is settled.
  def rate? = client? && record.accepted? && record.rating.nil?

  # --- The designer's ---------------------------------------------------------

  def claim? = designer_user? && record.claimable_by?(user.designer_profile)

  def deliver? = designer? && record.may_deliver?

  def return_to_client? = designer? && record.may_return_to_client?

  # Both sides write; an administrator reads.
  def message? = (client? || designer?) && record.open?

  # --- The administration's ---------------------------------------------------
  #
  # An administrator does not rejoin the conversation or deliver files: they
  # settle what the two sides could not, and only while it is still open.
  def settle? = user&.admin? && record.may_cancel?

  class AdminScope < ApplicationPolicy::Scope
    def resolve
      raise Pundit::NotAuthorizedError unless user&.admin?

      scope.all
    end
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.nil?

      if user.client?
        scope.where(client: user)
      elsif user.designer?
        designer_scope
      else
        scope.none
      end
    end

    private
      # What a designer may see: their own reviews, plus the queue they could
      # take from. A queued review nobody owns yet is visible to everyone who
      # could do it — that is what "first available" means.
      def designer_scope
        # Même raison que dans PrintRequestPolicy : la policy charge ce dont elle
        # a besoin, au lieu de l'atteindre depuis l'utilisateur courant.
        profile = DesignerProfile.includes(:review_levels).find_by(user_id: user.id)
        return scope.none if profile.nil?

        scope.where(designer_profile: profile)
             .or(scope.where(status: "queued", review_level: profile.review_levels))
      end
  end

  private
    def client? = user.present? && record.client_id == user.id

    def designer_user? = user&.designer? && user.designer_profile.present?

    def designer? = designer_user? && record.designer_profile_id == user.designer_profile.id

    def owns_design? = record.design&.user_id == user&.id
end
