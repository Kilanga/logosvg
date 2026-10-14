# The data export as one ZIP archive: the JSON of AccountExport, and the files
# the account may take (decided on 14/10/2026 — docs/SPEC.md, « RGPD »: JSON
# and files).
#
# Which files is the same rule as everywhere else: a client gets the
# watermarked rendering of each finished design and the pictures they
# uploaded themselves, never a print file — that goes to workshops and
# designers only. A workshop gets its logo and photos, a designer their
# avatar and portfolio: what they put on the site.
class AccountArchive
  JSON_NAME = "donnees.json".freeze

  def self.call(...) = new(...).call

  def initialize(user:, host:)
    @user = user
    @host = host
  end

  # The archive's bytes.
  def call
    buffer = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry(JSON_NAME)
      zip.write(JSON.pretty_generate(AccountExport.call(user: @user, host: @host)))

      files.each do |path, bytes|
        zip.put_next_entry(path)
        zip.write(bytes)
      end
    end
    buffer.string
  end

  private
    # [path in the archive, bytes], each path unique.
    def files
      (design_files + printer_files + designer_files).uniq(&:first)
    end

    def design_files
      Design.where(user_id: @user.id).with_attached_print_file.with_attached_reference_image
            .includes(printer: :subscription).flat_map do |design|
        found = []
        if design.ready? && (preview = DesignPreview.call(design))
          found << [ "designs/#{design.token}-apercu.png", preview ]
        end
        if design.reference_image.attached?
          found << [ "designs/#{design.token}-mon-image#{extension(design.reference_image)}", design.reference_image.download ]
        end
        found
      end
    end

    def printer_files
      shop = Printer.with_attached_logo.with_attached_photos.find_by(user_id: @user.id)
      return [] if shop.nil?

      logo = shop.logo.attached? ? [ [ "atelier/logo#{extension(shop.logo)}", shop.logo.download ] ] : []
      logo + shop.photos.each_with_index.map do |photo, index|
        [ "atelier/photo-#{index + 1}#{extension(photo)}", photo.download ]
      end
    end

    def designer_files
      profile = DesignerProfile.with_attached_avatar.with_attached_portfolio.find_by(user_id: @user.id)
      return [] if profile.nil?

      avatar = profile.avatar.attached? ? [ [ "graphiste/avatar#{extension(profile.avatar)}", profile.avatar.download ] ] : []
      avatar + profile.portfolio.each_with_index.map do |piece, index|
        [ "graphiste/portfolio-#{index + 1}#{extension(piece)}", piece.download ]
      end
    end

    def extension(attachment) = File.extname(attachment.filename.to_s).downcase.presence || ".bin"
end
