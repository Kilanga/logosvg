# The watermarked preview of a delivered version, for the three who look at a
# review: its client, its designer and the administration (ReviewPolicy#show?).
# Outside the client space for the same reason as DesignPreviewsController: the
# designer and the administration would be turned away before the policy spoke.
class ReviewVersionPreviewsController < ApplicationController
  def show
    review = Review.includes(:design).find_by!(token: params[:token])
    authorize review, :show?

    version = review.versions.with_attached_file.find_by!(number: params[:number])
    preview = VersionPreview.call(version)
    return head :not_found if preview.nil?

    send_data preview, type: "image/png", disposition: "inline",
                       filename: "#{review.token}-version-#{version.number}.png"
  end
end
