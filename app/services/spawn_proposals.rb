# Turns a new design into the first of the proposals one click draws.
#
# Since October 2026 a creation draws several images at once, each with its
# own graphic take, and the client keeps one. The siblings exist from the
# moment the form is sent — pending, without a job yet — so the page the client
# lands on already shows every slot filling in, rather than one image that
# later turns into three. GenerateDesignJob hands each of them its job id.
#
# The click is counted once, on the first design: the siblings share its batch
# token, and every count — the workshop's month, the lineage's reprises — reads
# batches, not rows.
class SpawnProposals
  def self.call(design, count: GeneratorClient.proposals) = new(design, count).call

  def initialize(design, count)
    @design = design
    @count = count.to_i
  end

  # Returns the siblings, without the design itself.
  def call
    return [] if @count <= 1

    token = SecureRandom.hex(8)
    Design.transaction do
      @design.update!(batch_token: token)
      Array.new(@count - 1) { build_sibling(token).tap(&:save!) }
    end
  end

  private
    def build_sibling(token)
      sibling = Design.new(
        user_id: @design.user_id,
        printer_id: @design.printer_id,
        mode: @design.mode,
        batch_token: token,
        prompt: @design.prompt,
        style: @design.style,
        technique: @design.technique,
        colors_requested: @design.colors_requested,
        print_width_cm: @design.print_width_cm,
        remove_background: @design.remove_background
      )
      copy_reference_image(sibling)
      sibling
    end

    # Each proposal is a lineage root of its own, and a root keeps the image
    # its children start from. Copied, not shared: a blob shared between
    # records is purged with the first of them.
    def copy_reference_image(sibling)
      return unless @design.reference_image.attached?

      sibling.reference_rights_confirmed = true
      sibling.reference_image.attach(io: StringIO.new(@design.reference_image.download),
                                     filename: @design.reference_image.filename.to_s,
                                     content_type: @design.reference_image.content_type)
    end
end
