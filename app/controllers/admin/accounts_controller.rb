module Admin
  # Every account, and deleting one. Deletion asks for the address typed out:
  # it cannot be undone, and a list of near-identical test addresses is exactly
  # where a click lands on the wrong row.
  class AccountsController < BaseController
    LIMIT = 50

    def index
      @query = params[:q].to_s.strip
      scope = policy_scope(User, policy_scope_class: UserPolicy::AdminScope)
                .where.not("email_address LIKE ?", AnonymiseAccount::EMAIL_PATTERN)
      scope = scope.matching(@query) if @query.present?
      @accounts = scope.order(created_at: :desc).limit(LIMIT)
    end

    def confirm_destroy
      @account = User.find(params[:id])
      authorize @account, :confirm_destroy?
    end

    def destroy
      @account = User.find(params[:id])
      authorize @account

      result = DeleteAccount.call(user: @account, by: Current.user, confirmation: params[:confirmation])

      if result.refused?
        flash.now[:alert] = t(".refused.#{result.reason}", email: @account.email_address)
        render :confirm_destroy, status: :unprocessable_entity
      else
        redirect_to admin_accounts_path,
                    notice: t(".#{result.outcome}", email: @account.email_address)
      end
    end
  end
end
