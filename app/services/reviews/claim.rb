module Reviews
  # A designer takes a review on.
  #
  # In "first available" mode several designers see the same row and may press
  # the button in the same second. The lock is what makes exactly one of them
  # win — checking `queued?` and then writing would let both through.
  class Claim
    Result = Data.define(:review, :error) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(review:, profile:)
      @review = review
      @profile = profile
    end

    def call
      Review.transaction do
        # Re-read inside the lock: whatever the screen said a moment ago, this
        # is the row as it stands now.
        @review.lock!

        return failure(refusal) unless @review.claimable_by?(@profile)

        @review.designer_profile = @profile
        @review.due_at = Time.current + @review.review_level.turnaround_hours.hours
        @review.claim!
        @review.save!
      end

      ReviewMailer.claimed(@review).deliver_later
      Result.new(review: @review, error: nil)
    end

    private
      def failure(message) = Result.new(review: @review, error: message)

      # Why not, in terms the designer can act on.
      def refusal
        return I18n.t("reviews.errors.already_taken") unless @review.queued?
        return I18n.t("designers.unavailable.#{@profile.unavailable_reason}") unless @profile.can_take_work?
        return I18n.t("reviews.errors.level_not_accepted") unless @profile.accepts?(@review.review_level)

        I18n.t("reviews.errors.not_for_you")
      end
  end
end
