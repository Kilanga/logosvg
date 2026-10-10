# The link email no longer goes through the platform (decided on 10/10/2026):
# the shop's own mail app opens with the message written, so nothing is sent
# from Brevo and nothing is left to count. The block keeps it reversible.
class DropWorkshopLinkEmails < ActiveRecord::Migration[8.1]
  def change
    drop_table :workshop_link_emails do |t|
      t.references :printer, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :recipient_digest, null: false
      t.timestamps

      t.index %i[ printer_id recipient_digest ], unique: true
      t.index %i[ printer_id created_at ]
    end
  end
end
