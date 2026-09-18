# Back to the name the Rails 8 authentication generator uses. Following the
# framework's own convention keeps the generated controllers, views and mailer
# unmodified, and keeps future upgrades boring.
class RenameUsersEmailToEmailAddress < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :email, :email_address
  end
end
