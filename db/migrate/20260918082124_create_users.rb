class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false

      t.string :first_name
      t.string :last_name
      t.string :phone
      t.string :city

      # client / printer / designer / admin. Defaults to the least privileged
      # role so a missing value can never produce an administrator.
      t.integer :role, null: false, default: 0

      t.datetime :terms_accepted_at

      # Soft delete: the account disappears from the application immediately and
      # is purged by a scheduled task later. See docs/SPEC.md, "RGPD".
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :role
    add_index :users, :deleted_at
  end
end
