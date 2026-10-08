module Designer
  # The designer's queue, and what they do with a review they have taken.
  class ReviewsController < BaseController
    before_action :set_review, except: :index

    def index
      authorize Review

      scope = policy_scope(Review).includes(:review_level, :client,
                                            design: :print_file_attachment)
      # Three lists, in the order a designer looks at them: what is mine to do,
      # what is waiting on the client, and what is finished.
      @mine = scope.where(designer_profile: profile, status: %w[ in_progress ]).order(:due_at)
      @waiting = scope.where(designer_profile: profile, status: %w[ delivered returned_to_client disputed ])
      # Empty when this designer could not take any of it: offering a button
      # that will be refused is worse than saying plainly why there is none.
      @available = if profile&.can_take_work?
        scope.awaiting_claim.where(designer_profile: [ nil, profile ]).newest_first
      else
        Review.none
      end
      @settled = scope.where(designer_profile: profile, status: %w[ accepted canceled ]).newest_first.limit(10)
    end

    def show
      authorize @review
      @versions = @review.versions.with_attached_file
      @messages = @review.messages.includes(:author)
      mark_client_messages_read
    end

    def claim
      authorize @review

      result = Reviews::Claim.call(review: @review, profile: profile)

      if result.success?
        redirect_to designer_review_path(@review), notice: t(".claimed")
      else
        redirect_to designer_reviews_path, alert: result.error
      end
    end

    def deliver
      authorize @review

      result = Reviews::DeliverVersion.call(
        review: @review, file: params[:file], message: params[:message],
        coverage: params[:coverage]&.to_unsafe_h
      )

      if result.success?
        redirect_to designer_review_path(@review), notice: t(".delivered", number: result.version.number)
      else
        redirect_to designer_review_path(@review), alert: result.error
      end
    end

    def return_to_client
      authorize @review

      result = Reviews::ReturnToClient.call(
        review: @review,
        reason: params[:reason],
        message: params[:message],
        proposed_level: ReviewLevel.offered.find_by(id: params[:proposed_level_id])
      )

      if result.success?
        redirect_to designer_reviews_path, notice: t(".returned")
      else
        redirect_to designer_review_path(@review), alert: result.error
      end
    end

    # The answer to a dispute: one more go, at no cost to the client.
    def offer_fix
      authorize @review

      result = Reviews::OfferFix.call(review: @review, author: Current.user, message: params[:fix_message])
      if result.success?
        redirect_to designer_review_path(@review), notice: t(".offered")
      else
        redirect_to designer_review_path(@review), alert: result.error
      end
    end

    # A custom job the designer and the client settled between themselves.
    def finish
      authorize @review

      @review.finish_off_platform!
      @review.save!
      CreateReviewedDesign.call(review: @review) if @review.delivered_any?
      ReviewMailer.finished_off_platform(@review).deliver_later

      redirect_to designer_reviews_path, notice: t(".finished")
    end

    def message
      authorize @review

      @review.messages.create!(author: Current.user, body: params[:body])
      redirect_to designer_review_path(@review)
    rescue ActiveRecord::RecordInvalid
      redirect_to designer_review_path(@review), alert: t(".empty")
    end

    private
      def profile = current_designer_profile

      # `:client` joins the show page here for the first time, alongside what it
      # already reads without ever having declared: the design and its level.
      # `strict_loading` had no test on this exact page to catch the gap before.
      def set_review
        @review = policy_scope(Review).includes(:client, :review_level, design: :print_file_attachment)
                                      .find_by!(token: params[:token])
      end

      def mark_client_messages_read
        @review.messages.unread.where.not(author: Current.user).find_each(&:read!)
      end
  end
end
