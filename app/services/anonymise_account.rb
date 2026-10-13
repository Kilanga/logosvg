# Empties an account the platform has to keep a row for.
#
# A print request and a review both refuse to lose their client by design —
# the workshop's job and the designer's payment outlive the account — so the
# user row stays and the person leaves it: name, address, telephone, password.
# Shared by the nightly purge of closed accounts and by an administrator's
# deletion of an account that still has such records.
class AnonymiseAccount
  EMAIL_PATTERN = "compte-supprime-%@invalid".freeze

  def self.call(user) = new(user).call

  def initialize(user)
    @user = user
  end

  # Raises when a record will not let go: a half-emptied account is worse than
  # one left alone for a human to look at.
  def call
    User.transaction do
      Session.where(user_id: @user.id).destroy_all
      Design.where(user_id: @user.id).strict_loading(false).find_each(&:destroy)

      @user.update_columns(
        email_address: "compte-supprime-#{@user.id}@invalid",
        first_name: I18n.t("privacy.anonymised"), last_name: "—",
        phone: nil, city: nil,
        password_digest: BCrypt::Password.create(SecureRandom.hex(32)),
        deleted_at: @user.deleted_at || Time.current,
        updated_at: Time.current
      )
    end
  end
end
