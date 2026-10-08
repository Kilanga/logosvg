module Reviews
  # The client says a delivery does not do what was asked.
  #
  # Decided on 08/10/2026. Until now a client out of corrections could only
  # accept, or wait for the week to run out and the designer to be paid
  # anyway. A dispute stops that clock: the designer can offer to put it right
  # at no cost, the client can change their mind, and otherwise an
  # administrator decides what the money does. Once per review, so it is a
  # recourse rather than a way to stall.
  class OpenDispute
    Result = Data.define(:error) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(review:, author:, reason:, message:)
      @review = review
      @author = author
      @reason = reason.to_s
      @message = message.to_s.strip
    end

    def call
      return failure(:not_disputable) unless @review.may_dispute?
      return failure(:reason) unless Review::DISPUTE_REASONS.include?(@reason)
      return failure(:message) if @message.length < 10

      Review.transaction do
        @review.dispute!
        @review.assign_attributes(dispute_reason: @reason, dispute_message: @message)
        @review.save!
        # In the conversation too: the designer answers there.
        @review.messages.create!(author: @author, body: @message)
      end

      ReviewMailer.dispute_opened(@review).deliver_later
      Result.new(error: nil)
    end

    private
      def failure(key) = Result.new(error: I18n.t("reviews.dispute.errors.#{key}"))
  end
end
