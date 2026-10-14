# The watermarked renderings of a design, for everyone who works on it.
#
# Not under /mon-espace: the workshop a design was sent to, the designers of
# its review and the administration see it too, and the client space would
# turn all of them away before the policy had a say (reported on 14/10/2026 —
# broken images in the workshop's print requests). Who may see a given design
# is DesignPolicy#image?'s answer, and only that.
#
# Shown in the page, not downloaded (reported the same day): opening the
# address shows the picture. `?telecharger=1` asks for the file, for the
# client's download button.
class DesignPreviewsController < ApplicationController
  before_action :set_design

  def show
    serve DesignPreview.call(@design), @design.token
  end

  # For comparison only — the "rendu final / image d'origine" selector. Also
  # watermarked, and never the deciding rendering: see DesignPreview.
  def original
    serve DesignPreview.call(@design, variant: :source_png), "#{@design.token}-original"
  end

  private
    def set_design
      @design = Design.with_attached_print_file.with_attached_source_png
                      .includes(printer: :subscription)
                      .find_by!(token: params[:token])
      authorize @design, :image?
    end

    def serve(preview, name)
      return head :not_found if preview.nil?

      send_data preview, type: "image/png", filename: "#{name}.png",
                         disposition: params[:telecharger].present? ? "attachment" : "inline"
    end
end
