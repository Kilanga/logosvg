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

  def self.call(upload) = new(upload).call

  def initialize(upload)
    @upload = upload
  end

  def call
    return failure(:too_large) if @upload.size > max_bytes

    # Sniffed from the bytes, not trusted from the browser or the extension.
    bytes = @upload.read
    type = Marcel::MimeType.for(StringIO.new(bytes))
    return failure(:wrong_type) unless ACCEPTED.include?(type)

    image = Vips::Image.new_from_buffer(bytes, "")
    image = image.autorot
    image = image.thumbnail_image(MAX_SIDE_PX, height: MAX_SIDE_PX, size: :down)
    png = image.write_to_buffer(".png", strip: true)

    Result.new(attachable: { io: StringIO.new(png), filename: "image-de-depart.png", content_type: "image/png" },
               error: nil)
  rescue Vips::Error
    failure(:unreadable)
  end

  private
    def max_bytes = Rails.application.config.tshirt.uploads[:max_photo_bytes]

    def failure(reason) = Result.new(attachable: nil, error: I18n.t("client.designs.reference_image.errors.#{reason}"))
end
