module Admin
  # An administrator settles a review that the two sides could not.
  #
  # Cancelling and refunding are one act, not two: a review closed without the
  # money moving leaves a client who paid for nothing, and a refund without the
  # closure leaves a designer who may still deliver. The amount is the
  # administrator's to name — a dispute is rarely all one way.
  #
  # Since 08/10/2026 it can also be split: with `pay_designer`, the review is
  # accepted rather than cancelled, the client gets back what the administrator
  # names, and the designer is paid for the rest — the commission applies to
  # what is paid, at the review's own rate. With nothing refunded, the
  # designer is simply paid in full.
  class SettleDispute
    Result = Data.define(:review, :error) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(review:, admin:, amount_cents:, note:, pay_designer: false)
      @review = review
      @admin = admin
      @amount_cents = amount_cents.to_i
      @note = note.to_s.strip
      @pay_designer = ActiveModel::Type::Boolean.new.cast(pay_designer) == true
    end

    def call
      return failure(:note_required) if @note.blank?
      return failure(:not_open) unless @review.may_cancel?
      return failure(:too_much) if @amount_cents > refundable
      return split if @pay_designer

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
      # Only work that was delivered can be paid for: the file is what the
      # client keeps.
      def split
        return failure(:nothing_delivered) unless @review.may_accept? && @review.delivered_any?
        return failure(:nothing_left) if @amount_cents >= refundable

        Review.transaction do
          payout = @review.payout_after_refund(@amount_cents)
          if @amount_cents.positive?
            Payments::RefundReview.call(review: @review, amount_cents: @amount_cents, notify: false)
          end

          @review.reload
          @review.accept!
          @review.assign_attributes(designer_payout_cents: payout, admin_note: @note,
                                    settled_by: @admin, settled_at: Time.current)
          @review.save!
        end

        Payments::SettleReview.call(review: @review)
        CreateReviewedDesign.call(review: @review)
        ReviewMailer.settled_by_admin(@review, @amount_cents).deliver_later
        Result.new(review: @review, error: nil)
      end

      def failure(reason) = Result.new(review: @review, error: I18n.t("admin.disputes.errors.#{reason}"))

      def refundable = @review.price_cents - @review.refunded_cents
  end
end
