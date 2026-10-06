# Marks a file as produced by generative AI, in a form machines read.
#
# Article 50(2) of the EU AI Act asks the provider of a generative system to
# mark its outputs "in a machine-readable format and detectable as artificially
# generated". This platform is that provider: it runs the model and hands the
# files on. The mark is metadata, not ink — it travels inside the file, never
# shows on a print, and costs the workshop nothing. That is why it stays on
# every file, the workshop's included; the visible mention lives on the
# previews and in the emails instead.
#
# The vocabulary is IPTC's Digital Source Type, carried in XMP: the identifier
# that image tools, stock agencies and C2PA readers already look for.
#
# - PNG: one iTXt chunk, keyword "XML:com.adobe.xmp", right after IHDR.
# - SVG: one <metadata> element, first child of the root.
#
# Idempotent: a file already marked comes back untouched. Anything that is
# neither PNG nor SVG comes back untouched too.
class AiProvenance
  # The whole image was drawn by the model.
  GENERATED = "trainedAlgorithmicMedia"
  # A person reworked an image the model drew — a designer's delivery.
  EDITED = "compositeWithTrainedAlgorithmicMedia"

  SOURCE_TYPE_URI = "http://cv.iptc.org/newscodes/digitalsourcetype/"
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b
  XMP_KEYWORD = "XML:com.adobe.xmp"
  MARKER = "digitalsourcetype/"

  def self.mark(bytes, content_type:, kind: GENERATED) = new(bytes, content_type, kind).mark

  def self.marked?(bytes) = bytes.to_s.b.include?(MARKER.b)

  def initialize(bytes, content_type, kind)
    @bytes = bytes.to_s
    @content_type = content_type.to_s
    @kind = kind
  end

  def mark
    return @bytes if self.class.marked?(@bytes)

    case @content_type
    when "image/png" then mark_png
    when "image/svg+xml" then mark_svg
    else @bytes
    end
  end

  private
    def description = I18n.t("ai_provenance.description", platform: platform)

    def platform = Rails.application.config.tshirt.platform_name

    # The source type is written as element text, not as an rdf:resource
    # attribute: SvgInspector refuses any attribute holding an http(s) URL, and
    # an XMP reader accepts both forms.
    def xmp
      <<~XML.strip
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:Iptc4xmpExt="http://iptc.org/std/Iptc4xmpExt/2008-02-29/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xmp="http://ns.adobe.com/xap/1.0/"><Iptc4xmpExt:DigitalSourceType>#{SOURCE_TYPE_URI}#{@kind}</Iptc4xmpExt:DigitalSourceType><xmp:CreatorTool>#{escape(platform)}</xmp:CreatorTool><dc:description><rdf:Alt><rdf:li xml:lang="fr">#{escape(description)}</rdf:li></rdf:Alt></dc:description></rdf:Description></rdf:RDF></x:xmpmeta>
      XML
    end

    def escape(text) = ERB::Util.html_escape(text)

    # A PNG is a signature then chunks: length, type, data, CRC. The XMP chunk
    # goes straight after IHDR, where readers look first; every other chunk is
    # copied byte for byte, so the picture itself is not touched.
    def mark_png
      bytes = @bytes.b
      return @bytes unless bytes.start_with?(PNG_SIGNATURE)

      ihdr_end = PNG_SIGNATURE.bytesize + 8 + bytes[8, 4].unpack1("N") + 4
      return @bytes if ihdr_end > bytes.bytesize || bytes[12, 4] != "IHDR"

      bytes[0, ihdr_end] + itxt_chunk + bytes[ihdr_end..]
    end

    # iTXt: keyword, null, compression flag 0, method 0, empty language tag,
    # null, empty translated keyword, null, then the UTF-8 text.
    def itxt_chunk
      data = "#{XMP_KEYWORD}\0\0\0\0\0".b + xmp.encode("UTF-8").b
      type = "iTXt".b
      [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
    end

    # Inserted as text right after the root's opening tag rather than through a
    # parse and re-serialisation: the vectoriser's output is left exactly as it
    # was, attribute for attribute, and the ink count read from it cannot move.
    def mark_svg
      text = @bytes.dup.force_encoding("UTF-8")
      opening = text.match(/<svg\b[^>]*>/m)
      return @bytes if opening.nil?
      return @bytes if opening[0].end_with?("/>")

      insert_at = opening.end(0)
      text[0...insert_at] + "<metadata id=\"ai-provenance\">#{xmp}</metadata>" + text[insert_at..]
    end
end
