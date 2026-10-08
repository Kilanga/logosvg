# The client's own image, offered as a starting point for the generation.
#
# Accepted as PNG, JPEG or WebP, then re-encoded here as a PNG no larger than
# the model works at: what is stored and sent is never the file the client
# uploaded. That is the privacy point — a phone photo carries its GPS position
# and camera details in EXIF, and re-encoding drops them — and it keeps a
# 10 Mo upload from travelling to the generation machine as is.
class ReferenceImage
  ACCEPTED = %w[ image/png image/jpeg image/webp ].freeze
  MAX_SIDE_PX = 1536

  Result = Data.define(:attachable, :error) do
    def success? = error.nil?
  end

  # A finished visual sent as is (mode "upload") keeps far more of its
  # definition: it is the print file, not a hint for the model.
  PRINT_SIDE_PX = 4096
  # What the generation service accepts in one request, once in base64. A
  # photo-like PNG at 4 096 px can weigh three times that: it is then brought
  # down step by step until it fits, rather than refused.
  MAX_PNG_BYTES = 11 * 1024 * 1024

  def self.call(upload, max_side: MAX_SIDE_PX) = new(upload, max_side).call

  def initialize(upload, max_side = MAX_SIDE_PX)
    @upload = upload
    @max_side = max_side
  end

  def call
    return failure(:too_large) if @upload.size > max_bytes

    # Sniffed from the bytes, not trusted from the browser or the extension.
    bytes = @upload.read
    type = Marcel::MimeType.for(StringIO.new(bytes))
    return failure(:wrong_type) unless ACCEPTED.include?(type)

    image = Vips::Image.new_from_buffer(bytes, "")
    image = image.autorot
    png = encode(image, @max_side)

    Result.new(attachable: { io: StringIO.new(png), filename: "image-de-depart.png", content_type: "image/png" },
               error: nil)
  rescue Vips::Error
    failure(:unreadable)
  end

  private
    def encode(image, side)
      png = image.thumbnail_image(side, height: side, size: :down).write_to_buffer(".png", strip: true)
      return png if png.bytesize <= MAX_PNG_BYTES || side <= MAX_SIDE_PX

      encode(image, (side * 0.8).to_i)
    end

    def max_bytes = Rails.application.config.tshirt.uploads[:max_photo_bytes]

    def failure(reason) = Result.new(attachable: nil, error: I18n.t("client.designs.reference_image.errors.#{reason}"))
end
