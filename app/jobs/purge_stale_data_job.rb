# Keeping data no longer than it is useful.
#
# Three retentions, each with its own reason:
#
#   - a design nobody ever sent to a workshop is a draft, and drafts expire;
#   - a print request is a commercial record, so it is anonymised rather than
#     deleted — the workshop's history of what it printed stays intact;
#   - a closed account is purged outright, except where a record has to remain.
#
# The durations are configured values, not constants buried here. See
# config/settings.yml and docs/SPEC.md, "RGPD".
class PurgeStaleDataJob < ApplicationJob
  queue_as :default

  def perform
    purge_unsent_designs
    anonymise_old_print_requests
    purge_closed_accounts
  end

  private
    def settings = Rails.application.config.tshirt.privacy

    # A design nobody asked anyone to print, past its retention. Soft-deleted
    # ones included: the client already said they were done with it.
    def purge_unsent_designs
      Design.where(created_at: ...settings[:design_retention_days].days.ago)
            .where.missing(:print_requests)
            .where.missing(:reviews)
            .find_each(&:destroy)
    end

    # The order stays; the person does not. What a workshop printed, in what
    # sizes, is its own commercial record — who asked for it stops being ours
    # to keep.
    def anonymise_old_print_requests
      PrintRequest.where(created_at: ...settings[:print_request_anonymize_days].days.ago)
                  .where.not(contact_email: nil)
                  .find_each do |request|
        request.update_columns(
          contact_name: I18n.t("privacy.anonymised"),
          contact_email: nil, contact_phone: nil, contact_city: nil,
          message: nil, updated_at: Time.current
        )
      end
    end

    # A closed account, past the grace period.
    #
    # The row is emptied rather than destroyed. A print request and a review
    # both refuse to lose their client by design — the workshop's job and the
    # designer's payment outlive the account — so destroying the user would
    # either fail or take a commercial record with it. What has to go is the
    # person, and that is what goes: name, address, telephone, password.
    def purge_closed_accounts
      User.deleted.where(deleted_at: ...settings[:deleted_account_purge_days].days.ago)
          .where.not("email_address LIKE ?", ANONYMISED_EMAIL_PATTERN)
          .find_each { |user| anonymise(user) }
    end

    # Already emptied: the sweep runs every day and must not keep rewriting the
    # same rows.
    ANONYMISED_EMAIL_PATTERN = "compte-supprime-%@invalid".freeze

    def anonymise(user)
      User.transaction do
        user.sessions.destroy_all
        user.designs.find_each(&:destroy)

        user.update_columns(
          email_address: "compte-supprime-#{user.id}@invalid",
          first_name: I18n.t("privacy.anonymised"), last_name: "—",
          phone: nil, city: nil,
          password_digest: BCrypt::Password.create(SecureRandom.hex(32)),
          updated_at: Time.current
        )
      end
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      # Left alone rather than half-purged: a record that will not let go is
      # one a human should look at.
      Rails.logger.error("[purge] could not purge account #{user.id}: #{e.class}")
    end
end
