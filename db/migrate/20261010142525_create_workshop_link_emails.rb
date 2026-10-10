# A shop emailing its link to a client it already spoke to (decided on
# 10/10/2026). One row per email sent: it is how the daily cap is counted, and
# how the same address is not written to twice by the same shop.
#
# The address itself is not kept — only a keyed digest of it, enough to
# recognise it again and useless to anyone reading the table. See
# `WorkshopLinkEmail.digest`.
class CreateWorkshopLinkEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :workshop_link_emails do |t|
      t.references :printer, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :recipient_digest, null: false
      t.timestamps
    end

    add_index :workshop_link_emails, %i[ printer_id recipient_digest ], unique: true
    add_index :workshop_link_emails, %i[ printer_id created_at ]
  end
end
