module Reviews
  # The client declines the proposed price but is not ready to give up: a new
  # designer, chosen just like the first one was, takes the review at the
  # level and price already paid.
  #
  # See docs/SPEC.md, "Renvoi au client par le graphiste".
  class PickDesigner
    Result = Data.define(:review, :error) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(review:, designer_profile_id:)
      @review = review
      @profile = DesignerProfile.listed.accepting.find_by(id: designer_profile_id)
    end

    def call
      return failure(:designer_required) if @profile.nil?
      return failure(:level_not_accepted) unless @profile.accepts?(@review.review_level)
      return failure(:already_refused) if already_refused?
      return failure(:reassignment_closed) unless @review.may_pick_new_designer?

      @review.assign_attributes(assignment_mode: "chosen", designer_profile: @profile, due_at: nil)
      @review.pick_new_designer!
      @review.save!

      ReviewMailer.notify_designers(@review).deliver_later
      Result.new(review: @review, error: nil)
    end

    private
      def failure(reason) = Result.new(review: @review, error: I18n.t("reviews.errors.#{reason}"))

      def already_refused?
        @review.refused_designer_profile_ids.include?(@profile.id) || @review.designer_profile_id == @profile.id
      end
  end
end
