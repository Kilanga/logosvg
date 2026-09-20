module Reviews
  # A designer hands a file back.
  #
  # The file is inspected before anything is stored, and it has to be the same
  # kind of file the design is: a designer does not return a PNG where the
  # workshop expects an SVG. What the inspection found is kept on the version,
  # so the client reads it without opening anything.
  class DeliverVersion
    Result = Data.define(:version, :error) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(review:, file:, message: nil)
      @review = review
      @file = file
      @message = message
    end

    def call
      return failure(t(:no_file)) if @file.blank?

      bytes = @file.read
      @file.rewind if @file.respond_to?(:rewind)

      inspection = inspect_file(bytes)
      return failure(inspection) if inspection.is_a?(String)

      version = store(inspection)
      advance

      ReviewMailer.version_delivered(@review, version).deliver_later
      Result.new(version: version, error: nil)
    end

    private
      def t(key, **options) = I18n.t("reviews.errors.#{key}", **options)

      def failure(message) = Result.new(version: nil, error: message)

      def design = @review.design

      # The format the workshop expects, decided when the design was generated.
      def inspect_file(bytes)
        if design.vector? then inspect_svg(bytes) else inspect_raster(bytes) end
      end

      def inspect_svg(bytes)
        result = SvgInspector.call(bytes)
        return t("svg.#{result.reason}", default: t(:svg_refused)) unless result.valid?

        result
      end

      def inspect_raster(bytes)
        result = RasterInspector.call(bytes, print_width_cm: design.print_width_cm)
        return t("raster.#{result.reason}", default: t(:raster_refused)) unless result.valid?

        result
      end

      def store(inspection)
        @review.versions.create!(
          message: @message,
          file: @file,
          inks_count: (inspection.inks if design.vector?),
          checks: checks_from(inspection)
        )
      end

      def checks_from(inspection)
        if design.vector?
          { "inks" => inspection.inks, "fills" => inspection.fills }
        else
          { "width_px" => inspection.width_px, "height_px" => inspection.height_px,
            "dpi" => inspection.dpi, "has_alpha" => inspection.has_alpha,
            "warnings" => inspection.warnings.map(&:to_s) }
        end
      end

      # A second version on a review already delivered is a delivery too: the
      # state only moves when there is somewhere to move from.
      def advance
        return unless @review.may_deliver?

        @review.deliver!
        @review.save!
      end
  end
end
