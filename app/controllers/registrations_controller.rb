# Sign-up. The visitor picks the role they are here for; `admin` is never
# offered. See docs/SPEC.md, "Rôles et parcours".
#
# A client account exists only through a workshop (decided on 09/10/2026): the
# role is offered once this visit knows one — its link, or its page reached from
# the directory. With the shop's code the account is admitted at once; without,
# a request goes to the shop and the account waits for its answer. See
# docs/SPEC.md, "Rattachement d'un client à un atelier".
class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  skip_after_action :verify_policy_scoped

  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_registration_path, alert: t("flash.rate_limited") }

  before_action :set_workshop

  def new
    # The home page links here with ?role=printer or ?role=designer, so the
    # right option is already selected when the form opens. A visitor a shop
    # sent is, unless they say otherwise, that shop's client.
    @user = User.new(role: requested_role(params[:role].presence || offered_roles.first))
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

    # Posted by hand, or the session expired between the shop's page and here:
    # said plainly rather than turned into another kind of account.
    if @user.client? && @workshop.nil?
      @user.validate
      @user.errors.add(:role, :workshop_required)
      return render :new, status: :unprocessable_entity
    end

    if save_with_workshop
      start_new_session_for @user
      redirect_to space_path_for(@user), notice: welcome_message
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    # The shop this sign-up would join: the one whose code came with this
    # visit, else the one the visit — or the agreed cookie — knows.
    def set_workshop
      id = shop_context.invited_printer_id || shop_context.printer_id
      @workshop = Printer.listed.find_by(id: id) if id
      # A new account has never been anyone's client: the poster or a sheet
      # admits it. See WorkshopEntry.
      @entry = WorkshopEntry.new(client: nil, printer: @workshop, shop_context: shop_context) if @workshop
      @invited = @entry&.admits? || false
    end

    # The account and its place with the shop are one thing: a client account
    # left without its request would be stuck with nothing to wait on.
    def save_with_workshop
      return @user.save unless @user.client?

      saved = User.transaction do
        raise ActiveRecord::Rollback unless @user.save

        # A sheet spent by someone else a moment ago: a request instead.
        unless @invited && @entry.admit!(@user)
          @invited = false
          @affiliation = ClientAffiliation.request!(client: @user, printer: @workshop)
        end
        true
      end

      AffiliationMailer.requested(@affiliation).deliver_later if saved && @affiliation
      saved
    end

    def welcome_message
      if @user.client? && !@invited
        t("registrations.create.welcome_pending", name: @user.first_name, workshop: @workshop.name)
      else
        t("registrations.create.welcome", name: @user.first_name)
      end
    end

    def registration_params
      params.expect(user: [ :email_address, :password, :password_confirmation,
                            :first_name, :last_name, :phone, :city, :role ])
            .then { |attributes| attributes.merge(role: posted_role(attributes[:role])) }
    end

    # What the form opens on: a role from the link when it is one on offer,
    # else the first that is.
    def requested_role(value)
      offered_roles.include?(value) ? value : offered_roles.first
    end

    # What was posted: the form is public, and its values cannot be trusted.
    # An unknown role — `admin` included — is no role, and the account is
    # refused rather than given one the visitor did not pick. A client with no
    # shop to join is refused in `create`, with its own message.
    def posted_role(value)
      User::SELF_ASSIGNABLE_ROLES.include?(value) ? value : nil
    end

    # The client role leads when a shop sent this visitor, and is absent when
    # none did: the page then speaks to workshops and designers.
    def offered_roles
      @workshop ? User::SELF_ASSIGNABLE_ROLES : User::SELF_ASSIGNABLE_ROLES - %w[ client ]
    end
    helper_method :offered_roles

    def robot_check_passed?
      TurnstileVerifier.call(token: params["cf-turnstile-response"], ip: request.remote_ip).then do |result|
        result.success? || result.skipped?
      end
    end
end
