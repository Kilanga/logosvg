# The watermarked rendering of a version a designer delivered (reported on
# 15/10/2026, blocking: the client was asked to accept, send back or dispute a
# file they had never seen). Drawn exactly as a design's preview — same width,
# same marks — from the version's own file, which never leaves for the client.
class VersionPreview < DesignPreview
  def self.call(version) = new(version).call

  def initialize(version)
    super(version.review.design)
    @version = version
  end

  private
    def attachment = @version.file

    def transparent? = false

    def cache_key = "version_preview/#{@version.id}/#{attachment.blob.checksum}/#{WIDTH_PX}"
end
