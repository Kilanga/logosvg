# Brings a finished generation home: downloads the print file and the original
# image, checks what came back, and marks the design ready.
#
# Kept out of PollDesignJob because this is where the judgement lives — what
# counts as an acceptable file, and what is recorded from the service's answer
# rather than recomputed.
class StoreGeneratedDesign
  # The service produced something the application will not serve.
  UnusableFile = Class.new(StandardError)

  CONTENT_TYPES = { "svg" => "image/svg+xml", "png" => "image/png" }.freeze

  def self.call(design:, answer:) = new(design: design, answer: answer).call

  def initialize(design:, answer:)
    @design = design
    @answer = answer
    @result = answer["result"] || {}
  end

  def call
    file_name = @result.fetch("print_file")
    bytes = client.download(@design.generator_job_id, file_name, user: @design.user)
    format = file_name.split(".").last

    inspect!(format, bytes)

    ActiveRecord::Base.transaction do
      attach(file_name, bytes, format)
      record_result(format)
      @design.succeed!
      @design.save!
    end

    DesignChannel.broadcast(@design)
    @design
  end

  private
    def client = @client ||= GeneratorClient.new

    # Only SVG is inspected for content: a PNG cannot carry a script, and its
    # type is checked by Active Storage on attachment.
    def inspect!(format, bytes)
      return unless format == "svg"

      result = SvgInspector.call(bytes)
      raise UnusableFile, "the generated SVG was refused: #{result.reason}" unless result.valid?

      @inspected = result
    end

    def attach(file_name, bytes, format)
      @design.print_file.attach(
        io: StringIO.new(bytes), filename: file_name,
        content_type: CONTENT_TYPES.fetch(format, "application/octet-stream")
      )

      source = client.download(@design.generator_job_id, "source.png", user: @design.user)
      @design.source_png.attach(io: StringIO.new(source), filename: "source.png", content_type: "image/png")
    rescue GeneratorClient::NotFound
      # The original image is a nicety for comparison, not the deliverable.
      Rails.logger.info("[generator] no source image for #{@design.token}")
    end

    # What the service says is what is recorded. The one exception is the ink
    # count on a vector file, which the inspector counted from the file itself —
    # and that is the number the workshop will see on its screens.
    def record_result(format)
      stats = @result["stats"] || {}

      @design.assign_attributes(
        print_format: format,
        palette: @result["palette"] || [],
        warnings: @result["warnings"] || [],
        stats: stats,
        prompt_used: @result["prompt_used"],
        subject: @result["subject"],
        seed: @result["seed"],
        refinements_left: @answer["refinements_left"],
        colors_requested: @result["colors"] || @design.colors_requested,
        inks_count: (@inspected&.inks || @result["inks"] if format == "svg"),
        paths_count: (stats["paths"] if format == "svg")
      )
    end
end
