module Admin
  # An administrator settles a review that the two sides could not.
  #
  # Cancelling and refunding are one act, not two: a review closed without the
  # money moving leaves a client who paid for nothing, and a refund without the
  # closure leaves a designer who may still deliver. The amount is the
  # administrator's to name — a dispute is rarely all one way.
  class SettleDispute
    Result = Data.define(:review, :error) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(review:, admin:, amount_cents:, note:)
      @review = review
      @admin = admin
      @amount_cents = amount_cents.to_i
      @note = note.to_s.strip
    end

    def call
      return failure(:note_required) if @note.blank?
      return failure(:not_open) unless @review.may_cancel?
      return failure(:too_much) if @amount_cents > refundable

      Review.transaction do
        # Quiet: the decision email below states the amount, and two messages
        # about one event read as a mistake.
        if @amount_cents.positive?
          Payments::RefundReview.call(review: @review, amount_cents: @amount_cents, notify: false)
        end

        @review.cancel!
        @review.assign_attributes(admin_note: @note, settled_by: @admin, settled_at: Time.current)
        @review.save!
      end

      ReviewMailer.settled_by_admin(@review, @amount_cents).deliver_later
      Result.new(review: @review, error: nil)
    end

    private
      def failure(reason) = Result.new(review: @review, error: I18n.t("admin.disputes.errors.#{reason}"))

      def refundable = @review.price_cents - @review.refunded_cents
  end
end
