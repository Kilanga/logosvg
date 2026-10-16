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
  #
  # Since 15/10/2026 the designer who took the review on keeps a guaranteed
  # share whatever is decided (Review#guaranteed_share_cents): the refund
  # stops short of it, and a cancellation pays it out.
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

      payout = @review.payout_after_refund(@amount_cents)
      payout = 0 if @review.guaranteed_share_cents.zero?

      return failure(:refund_failed) unless refunded?

      Review.transaction do
        @review.reload
        @review.cancel!
        @review.assign_attributes(admin_note: @note, settled_by: @admin, settled_at: Time.current,
                                  designer_payout_cents: (payout if payout.positive?))
        @review.save!
      end

      Payments::SettleReview.call(review: @review, notify: false) if payout.positive?
      notify
      Result.new(review: @review, error: nil)
    end

    private
      # Only work that was delivered can be paid for: the file is what the
      # client keeps.
      def split
        return failure(:nothing_delivered) unless @review.may_accept? && @review.delivered_any?
        return failure(:nothing_left) unless @review.payout_after_refund(@amount_cents).positive?

        payout = @review.payout_after_refund(@amount_cents)
        return failure(:refund_failed) unless refunded?

        Review.transaction do
          @review.reload
          @review.accept!
          @review.assign_attributes(designer_payout_cents: payout, admin_note: @note,
                                    settled_by: @admin, settled_at: Time.current)
          @review.save!
        end

        Payments::SettleReview.call(review: @review, notify: false)
        CreateReviewedDesign.call(review: @review)
        notify
        Result.new(review: @review, error: nil)
      end

      # Stripe first, outside any transaction: a call to Stripe cannot be rolled
      # back, and the decision is only recorded once the money has moved
      # (reported on 16/10/2026: a refused refund closed the review all the
      # same, and the email said the client had been refunded). Quiet: the
      # decision email states the amount, and two messages read as a mistake.
      def refunded?
        return true unless @amount_cents.positive?

        !Payments::RefundReview.failed?(
          Payments::RefundReview.call(review: @review, amount_cents: @amount_cents, notify: false)
        )
      end

      # Each side gets its own email (reported on 15/10/2026: both were in
      # « À », each reading the other's address).
      def notify
        ReviewMailer.settled_by_admin(@review, @amount_cents, recipient: "client").deliver_later
        return if @review.designer_profile_id.nil?

        ReviewMailer.settled_by_admin(@review, @amount_cents, recipient: "designer").deliver_later
      end

      def failure(reason) = Result.new(review: @review, error: I18n.t("admin.disputes.errors.#{reason}"))

      def refundable = @review.refundable_cents
  end
end
