# Sends a design to a workshop, once.
#
# The whole point of this object is that sending is not saving: the request
# takes its own copies of the print file and of the preview, stamps the time,
# and only then are the emails queued. A design that later fathers a variant, or
# is deleted, must not change what a workshop has in hand.
class SendPrintRequest
  Result = Data.define(:print_request, :error) do
    def success? = error.nil?
  end

  # The design must be printable by this shop before anything is copied: an
  # email that reaches a workshop which cannot do the job wastes both sides'
  # time, and the directory already said so on screen.
  Incompatible = Class.new(StandardError)

  def self.call(...) = new(...).call

  def initialize(print_request:)
    @print_request = print_request
  end

  def call
    design = @print_request.design

    compatibility = design.compatibility_with(@print_request.printer)
    return failure(compatibility.message) unless compatibility.compatible?
    return failure(I18n.t("print_requests.errors.design_not_ready")) unless design.ready?

    PrintRequest.transaction do
      copy_files(design)
      @print_request.sent_at = Time.current
      @print_request.save!
    end

    PrintRequestMailer.to_printer(@print_request).deliver_later
    PrintRequestMailer.to_client(@print_request).deliver_later

    Result.new(print_request: @print_request, error: nil)
  end

  private
    def failure(message) = Result.new(print_request: @print_request, error: message)

    # Copies, not references: `attach`ing the same blob would tie the request's
    # file to the design's, and deleting the design would take the workshop's
    # copy with it.
    def copy_files(design)
      attach_copy(design.print_file, to: @print_request.final_file)

      preview = DesignPreview.call(design)
      return if preview.nil?

      @print_request.preview_png.attach(
        io: StringIO.new(preview), filename: "#{design.token}-apercu.png", content_type: "image/png"
      )
    end

    def attach_copy(source, to:)
      return unless source.attached?

      source.blob.open do |file|
        to.attach(io: File.open(file.path), filename: source.filename.to_s,
                  content_type: source.content_type)
      end
    end
end
