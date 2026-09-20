module Admin
  # Reviews, and the ones that went wrong.
  #
  # An administrator reads a dispute; they do not rejoin the conversation or
  # deliver files. What they can do is end it and decide what the money does.
  class ReviewsController < BaseController
    before_action :set_review, only: %i[ show settle ]

    FILTERS = %w[ open disputed returned settled all ].freeze

    def index
      authorize Review

      @filter = FILTERS.include?(params[:filtre]) ? params[:filtre] : "open"
      @counts = counts
      @reviews = filtered.includes(:client, :review_level, :designer_profile, :design)
                         .newest_first.limit(50)
    end

    def show
      authorize @review
      @versions = @review.versions.with_attached_file
      @messages = @review.messages.includes(:author)
    end

    def settle
      authorize @review, :settle?

      result = Admin::SettleDispute.call(
        review: @review, admin: Current.user,
        amount_cents: euros_to_cents(params[:refund]), note: params[:note]
      )

      if result.success?
        redirect_to admin_reviews_path, notice: t(".settled")
      else
        redirect_to admin_review_path(@review), alert: result.error
      end
    end

    private
      def scope = policy_scope(Review, policy_scope_class: ReviewPolicy::AdminScope)

      def set_review = @review = scope.find_by!(token: params[:token])

      def counts
        {
          "open" => scope.where(status: %w[ queued in_progress delivered ]).count,
          "disputed" => disputed.count,
          "returned" => scope.where(status: "returned_to_client").count,
          "settled" => scope.where.not(settled_at: nil).count,
          "all" => scope.count
        }
      end

      def filtered
        case @filter
        when "disputed" then disputed
        when "returned" then scope.where(status: "returned_to_client")
        when "settled" then scope.where.not(settled_at: nil)
        when "all" then scope
        else scope.where(status: %w[ queued in_progress delivered ])
        end
      end

      # What "needs a human" looks like without a dispute flag: work that has
      # run past its deadline, and work delivered long enough ago that the
      # client is plainly not answering.
      def disputed
        scope.where(status: "in_progress").where(due_at: ...Time.current)
             .or(scope.where(status: "delivered")
                      .where(delivered_at: ...auto_accept_days.days.ago))
      end

      def auto_accept_days = Rails.application.config.tshirt.reviews[:auto_accept_days]

      # Euros on the form, cents in the database — never a float for money.
      def euros_to_cents(value)
        return 0 if value.blank?

        (value.to_s.tr(",", ".").to_d * 100).to_i
      end
  end
end
