# Sign-up. The visitor picks the role they are here for; `admin` is never
# offered. See docs/SPEC.md, "Rôles et parcours".
class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  skip_after_action :verify_policy_scoped

  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_registration_path, alert: t("flash.rate_limited") }

  def new
    # The home page links here with ?role=printer or ?role=designer, so the
    # right option is already selected when the form opens.
    @user = User.new(role: requested_role(params[:role]))
    authorize @user
  end

  def create
    @user = User.new(registration_params)
    authorize @user

    @user.terms_accepted_at = Time.current if params.dig(:user, :terms).present?

    unless robot_check_passed?
      @user.validate
      flash.now[:alert] = t("flash.turnstile_failed")
      return render :new, status: :unprocessable_entity
    end

    if @user.save
      start_new_session_for @user
      redirect_to space_path_for(@user), notice: t("registrations.create.welcome", name: @user.first_name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def registration_params
      params.expect(user: [ :email_address, :password, :password_confirmation,
                            :first_name, :last_name, :phone, :city, :role ])
            .then { |attributes| attributes.merge(role: requested_role(attributes[:role])) }
    end

    # An unknown or missing role falls back to the least privileged one rather
    # than raising: the form is public, and its values cannot be trusted.
    def requested_role(value)
      User::SELF_ASSIGNABLE_ROLES.include?(value) ? value : "client"
    end

    def robot_check_passed?
      TurnstileVerifier.call(token: params["cf-turnstile-response"], ip: request.remote_ip).then do |result|
        result.success? || result.skipped?
      end
    end
end
