module Public
  # The page a workshop opens from its email, without an account.
  #
  # The link only ever *shows* the page. Acknowledging is a POST from a button
  # on it, because mail scanners and antivirus software follow links on their
  # own — a GET that changed the status would mark every request acknowledged
  # before a human had read it. See docs/SPEC.md, "Demande d'impression".
  class PrintRequestConfirmationsController < BaseController
    # Nothing here is scoped to a signed-in user: the bearer of an unguessable
    # token is the audience, and the token is the authorization.
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped

    before_action :set_print_request

    def show
    end

    def create
      unless @print_request.confirmable?
        return render :show, status: :unprocessable_entity
      end

      @print_request.acknowledge!
      @print_request.save!

      PrintRequestMailer.status_changed(@print_request).deliver_later

      redirect_to print_request_confirmation_path(params[:token]), notice: t(".acknowledged")
    end

    private
      # A token that matches nothing, and one that has expired, are the same
      # answer to whoever is holding the link.
      def set_print_request
        @print_request = PrintRequest.find_by(confirmation_token: params[:token])

        head :not_found if @print_request.nil?
      end
  end
end
