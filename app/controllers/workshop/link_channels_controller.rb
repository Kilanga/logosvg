module Workshop
  # The named links of a shop: one for the flyer, one for the trade show, one
  # for the Instagram bio. Made and removed from the link screen.
  class LinkChannelsController < BaseController
    skip_after_action :verify_policy_scoped

    before_action :set_printer

    # Atelier+ only: a channel without statistics to read it in would be a link
    # like any other.
    def create
      authorize @printer, :manage_link_channels?

      channel = @printer.link_channels.build(channel_params)

      if channel.save
        redirect_to workshop_link_share_path, notice: t(".created", label: channel.label)
      else
        redirect_to workshop_link_share_path, alert: channel.errors.full_messages.to_sentence
      end
    end

    # Open to every shop, subscribed or not: a shop that stops paying must still
    # be able to tidy what it made.
    def destroy
      authorize @printer, :update?

      channel = @printer.link_channels.find_by!(key: params[:key])
      channel.destroy!

      redirect_to workshop_link_share_path, notice: t(".destroyed", label: channel.label)
    end

    private
      # No listing, no link to name: the same door as the link screen itself.
      def set_printer
        @printer = current_printer
        redirect_to edit_workshop_profile_path unless @printer&.persisted?
      end

      def channel_params = params.expect(link_channel: [ :label ])
  end
end
