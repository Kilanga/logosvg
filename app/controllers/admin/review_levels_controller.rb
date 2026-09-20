module Admin
  # What a review costs and promises.
  #
  # Editing a level never rewrites a review already bought: the price, the fee
  # and the allowance were copied onto the row at purchase. That is what makes
  # this screen safe to use.
  class ReviewLevelsController < BaseController
    def index
      @levels = policy_scope(ReviewLevel, policy_scope_class: ReviewLevelPolicy::Scope).order(:position)
      authorize ReviewLevel
    end

    def create
      @level = ReviewLevel.new(level_params)
      authorize @level

      if @level.save
        redirect_to admin_levels_path, notice: t(".created", name: @level.name)
      else
        @levels = ReviewLevel.order(:position)
        render :index, status: :unprocessable_entity
      end
    end

    def update
      @level = ReviewLevel.find(params[:id])
      authorize @level

      if @level.update(level_params)
        redirect_to admin_levels_path, notice: t(".saved", name: @level.name)
      else
        @levels = ReviewLevel.order(:position)
        render :index, status: :unprocessable_entity
      end
    end

    private
      # Euros on the form, cents in the database. A blank price means "quoted",
      # which only the custom level is allowed to be.
      def level_params
        attributes = params.expect(review_level: [
          :key, :name, :description, :price, :turnaround_hours,
          :revisions_included, :position, :active
        ])

        attributes.to_h.except("price").merge("price_cents" => euros_to_cents(attributes[:price]))
      end

      def euros_to_cents(value)
        return nil if value.blank?

        (value.to_s.tr(",", ".").to_d * 100).to_i
      end
  end
end
