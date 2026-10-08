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
    bytes = client.download(@design.generator_job_id, file_name, user_id: @design.user_id)
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

    # Drawn from the client's own image: the model reworked existing content,
    # which IPTC calls a composite rather than a pure generation.
    def provenance
      @result["from_image"] ? AiProvenance::EDITED : AiProvenance::GENERATED
    end

    # A client's own image is marked only when the client declared it drawn by
    # an AI — and then as generated: the platform only changed its format.
    def marked(bytes, content_type)
      return bytes unless @design.ai_generated?

      kind = @design.upload? ? AiProvenance::GENERATED : provenance
      AiProvenance.mark(bytes, content_type: content_type, kind: kind)
    end

    # Only SVG is inspected for content: a PNG cannot carry a script, and its
    # type is checked by Active Storage on attachment.
    def inspect!(format, bytes)
      return unless format == "svg"

      result = SvgInspector.call(bytes)
      raise UnusableFile, "the generated SVG was refused: #{result.reason}" unless result.valid?

      @inspected = result
    end

    # Both files are marked as AI-generated before they are stored: every copy
    # made later — the workshop's included — inherits the mark. See AiProvenance.
    def attach(file_name, bytes, format)
      content_type = CONTENT_TYPES.fetch(format, "application/octet-stream")
      @design.print_file.attach(
        io: StringIO.new(marked(bytes, content_type)),
        filename: file_name, content_type: content_type
      )

      source = client.download(@design.generator_job_id, "source.png", user_id: @design.user_id)
      @design.source_png.attach(io: StringIO.new(marked(source, "image/png")),
                                filename: "source.png", content_type: "image/png")
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
        refinements_left: (@design.upload? ? nil : [ @answer["refinements_left"], @design.refinements_remaining ].compact.min),
        colors_requested: recorded_colors,
        inks_count: (@inspected&.inks || @result["inks"] if format == "svg"),
        paths_count: (stats["paths"] if format == "svg")
      )
    end

    # `colors_requested` est le budget d'encres du client, et il n'existe que
    # pour les techniques qui en comptent. Le service, lui, renvoie toujours un
    # nombre : pour le DTF, le DTG et la sublimation, c'est son propre défaut —
    # huit — parce que ces machines impriment en quadrichromie.
    #
    # Le reprendre tel quel écrivait 8 dans une colonne validée entre 1 et 6.
    # L'enregistrement devenait invalide, `succeed!` levait, la transaction
    # était annulée, et le design restait « en cours » pour toujours.
    def recorded_colors
      entry = PrintTechniques.find(@design.technique)
      return @design.colors_requested unless entry&.limited_colors?

      @result["colors"] || @design.colors_requested
    end
end
