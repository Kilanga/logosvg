module Client
  # The client's own details and password.
  #
  # Two forms, two actions: changing an address and changing a password fail in
  # different ways and must not share a single set of error messages. Exporting
  # and closing the account arrive at step 10.
  class AccountsController < BaseController
    skip_after_action :verify_policy_scoped

    def edit
      @user = Current.user
      authorize @user, :update?
    end

    def update
      @user = Current.user
      authorize @user, :update?

      if @user.update(account_params)
        redirect_to client_account_path, notice: t(".saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # The current password is asked for even though the visitor is signed in: a
    # borrowed, unlocked browser is the case this guards against.
    def update_password
      @user = Current.user
      authorize @user, :update?

      unless @user.authenticate(params.dig(:user, :current_password).to_s)
        @user.errors.add(:current_password, :invalid)
        return render :edit, status: :unprocessable_entity
      end

      if @user.update(password_params)
        # Every other session is dropped: changing a password is how someone
        # locks out whoever they think is reading their mail.
        Session.where(user_id: Current.user.id).where.not(id: Current.session.id).destroy_all
        redirect_to client_account_path, notice: t(".changed")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Everything the platform holds about this account, as JSON. Served rather
    # than emailed: the person asking is signed in, and a file that lands in an
    # inbox is a copy nobody can take back.
    def export
      @user = Current.user
      authorize @user, :update?

      send_data JSON.pretty_generate(AccountExport.call(user: @user, host: request.host_with_port)),
                type: "application/json", disposition: "attachment",
                filename: "#{t('.filename')}-#{Date.current.iso8601}.json"
    end

    # Closing the account. Not destroyed here: print requests and reviews are
    # commercial records that outlive it, and the purge task empties the row a
    # month later. What happens now is that the account stops working.
    def destroy
      @user = Current.user
      authorize @user, :update?

      unless @user.authenticate(params[:current_password].to_s)
        @user.errors.add(:current_password, :invalid)
        return render :edit, status: :unprocessable_entity
      end

      @user.soft_delete!
      redirect_to root_path, notice: t(".closed")
    end

    private
      # The role is not here, and neither is the email confirmation flow: an
      # account changes hands through neither of them.
      def account_params
        params.expect(user: [ :first_name, :last_name, :phone, :city ])
      end

      def password_params
        params.expect(user: [ :password, :password_confirmation ])
      end
  end
end
