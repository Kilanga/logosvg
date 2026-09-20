module Client
  # Asking a designer to check a design, and everything the client does with
  # the review afterwards.
  class ReviewsController < BaseController
    before_action :set_design, only: %i[ new create ]
    before_action :set_review, except: %i[ index new create ]

    rate_limit to: 10, within: 1.minute, only: %i[ create message ],
               with: -> { redirect_to client_reviews_path, alert: t("flash.rate_limited") }

    def index
      authorize Review
      @reviews = policy_scope(Review).newest_first
                                     .includes(:review_level, :designer_profile,
                                               design: :print_file_attachment)
    end

    def new
      @review = build_review
      authorize @review
      @levels = ReviewLevel.offered
    end

    # The review row exists before Stripe does: the webhook comes back with a
    # session id and nothing else to hang it on.
    def create
      @review = build_review(review_params)
      authorize @review

      unless @review.save
        @levels = ReviewLevel.offered
        return render :new, status: :unprocessable_entity
      end

      checkout
    end

    def show
      authorize @review
      @versions = @review.versions.with_attached_file
      @messages = @review.messages.includes(:author)
      mark_designer_messages_read
    end

    def accept
      authorize @review

      @review.accept!
      @review.save!
      Payments::SettleReview.call(review: @review)

      redirect_to review_path(@review), notice: t(".accepted")
    end

    def revision
      authorize @review

      body = params[:body].to_s.strip
      return redirect_to review_path(@review), alert: t(".message_required") if body.blank?

      Review.transaction do
        @review.messages.create!(author: Current.user, body: body)
        @review.request_revision!
        @review.due_at = Time.current + @review.review_level.turnaround_hours.hours
        @review.save!
      end

      ReviewMailer.revision_requested(@review).deliver_later
      redirect_to review_path(@review), notice: t(".requested")
    end

    # Upwards costs the difference and goes through Checkout; downwards or
    # level-for-level is applied at once and the difference comes back.
    def accept_proposal
      authorize @review

      if @review.proposal_difference_cents.positive?
        upgrade_checkout
      else
        refund_difference
        Reviews::ApplyProposal.call(review: @review)
        redirect_to review_path(@review), notice: t(".accepted")
      end
    end

    def decline_proposal
      authorize @review

      Payments::RefundReview.call(review: @review, amount_cents: @review.price_cents)
      @review.decline_proposal!
      @review.save!

      redirect_to review_path(@review), notice: t(".declined")
    end

    # The chosen designer went quiet. The client opens it to everyone rather
    # than waiting longer.
    def reopen
      authorize @review

      @review.update!(assignment_mode: "first_available", designer_profile: nil)
      ReviewMailer.notify_designers(@review).deliver_later

      redirect_to review_path(@review), notice: t(".reopened")
    end

    def rate
      authorize @review

      @review.update(rating: params[:rating], rating_comment: params[:comment])
      refresh_designer_rating

      redirect_to review_path(@review), notice: t(".rated")
    end

    def message
      authorize @review

      @review.messages.create!(author: Current.user, body: params[:body])
      redirect_to review_path(@review)
    rescue ActiveRecord::RecordInvalid
      redirect_to review_path(@review), alert: t(".empty")
    end

    private
      def set_design
        @design = policy_scope(Design).find_by!(token: params[:design_token])
      end

      def set_review
        @review = policy_scope(Review).find_by!(token: params[:token])
      end

      def build_review(attributes = {})
        level = ReviewLevel.offered.find_by(id: attributes[:review_level_id])
        profile = chosen_profile(attributes[:designer_profile_id])

        Review.new(
          design: @design, client: Current.user,
          review_level: level,
          designer_profile: profile,
          assignment_mode: profile ? "chosen" : "first_available",
          client_brief: attributes[:client_brief],
          # Copied now, on purpose: a level whose price changes next month must
          # not rewrite what was paid.
          price_cents: level&.price_cents.to_i,
          platform_fee_cents: level&.platform_fee_cents.to_i,
          revisions_included: level&.revisions_included.to_i
        )
      end

      # Only a designer who could actually do it.
      def chosen_profile(id)
        return nil if id.blank?

        DesignerProfile.listed.accepting.find_by(id: id)
      end

      def checkout
        result = Payments::StartReviewCheckout.call(
          review: @review, amount_cents: @review.price_cents,
          success_url: review_url(@review), cancel_url: new_design_review_url(@design)
        )

        if result.success?
          redirect_to result.url, allow_other_host: true
        else
          redirect_to review_path(@review), alert: result.error
        end
      end

      def upgrade_checkout
        result = Payments::StartReviewCheckout.call(
          review: @review, amount_cents: @review.proposal_difference_cents, purpose: :upgrade,
          success_url: review_url(@review), cancel_url: review_url(@review)
        )

        if result.success?
          redirect_to result.url, allow_other_host: true
        else
          redirect_to review_path(@review), alert: result.error
        end
      end

      # A cheaper level means money back before the work restarts.
      def refund_difference
        owed = -@review.proposal_difference_cents
        return unless owed.positive?

        Payments::RefundReview.call(review: @review, amount_cents: owed)
      end

      def refresh_designer_rating
        profile = @review.designer_profile
        return if profile.nil?

        rated = Review.where(designer_profile: profile).where.not(rating: nil)
        profile.update!(rating_avg: rated.average(:rating), ratings_count: rated.count)
      end

      def mark_designer_messages_read
        @review.messages.unread.where.not(author: Current.user).find_each(&:read!)
      end

      def review_params
        params.expect(review: [ :review_level_id, :designer_profile_id, :client_brief ])
      end
  end
end
