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
      @waiting = scope.where(designer_profile: profile, status: %w[ delivered returned_to_client ])
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
        review: @review, file: params[:file], message: params[:message]
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
        proposed_level: ReviewLevel.offered.find_by(id: params[:proposed_level_id]),
        proposed_price_cents: proposed_price_cents
      )

      if result.success?
        redirect_to designer_reviews_path, notice: t(".returned")
      else
        redirect_to designer_review_path(@review), alert: result.error
      end
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

      def set_review
        @review = policy_scope(Review).find_by!(token: params[:token])
      end

      # Euros on the form, cents in the database — never a float for money.
      def proposed_price_cents
        euros = params[:proposed_price]
        return nil if euros.blank?

        (euros.to_s.tr(",", ".").to_d * 100).to_i
      end

      def mark_client_messages_read
        @review.messages.unread.where.not(author: Current.user).find_each(&:read!)
      end
  end
end
