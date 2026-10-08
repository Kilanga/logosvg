module Reviews
  # The designer answers a dispute by offering one more go, at no cost to the
  # client. Most disagreements end here, between the two people concerned,
  # without anyone deciding for them.
  class OfferFix
    Result = Data.define(:error) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(review:, author:, message:)
      @review = review
      @author = author
      @message = message.to_s.strip
    end

    def call
      return failure(:not_disputed) unless @review.disputed?
      return failure(:already_offered) if @review.fix_offered?
      return failure(:message) if @message.length < 10

      Review.transaction do
        @review.update!(fix_offered_at: Time.current)
        @review.messages.create!(author: @author, body: @message)
      end

      ReviewMailer.fix_offered(@review).deliver_later
      Result.new(error: nil)
    end

    private
      def failure(key) = Result.new(error: I18n.t("reviews.dispute.errors.#{key}"))
  end
end
