# The numbered single-use sheets are gone (decided on 10/10/2026). Now that the
# shop validates a former client's return, the counter poster can be handed
# out as well, and the email to a client carries the shop's link: nothing is
# left for a sheet to do. The block keeps the migration reversible.
class DropWorkshopInvites < ActiveRecord::Migration[8.1]
  def change
    drop_table :workshop_invites do |t|
      t.references :printer, null: false, foreign_key: { on_delete: :cascade }
      t.integer :batch, null: false
      t.integer :number, null: false
      t.string :code, null: false
      t.references :used_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :used_at
      t.datetime :revoked_at
      t.timestamps

      t.index :code, unique: true
      t.index %i[ printer_id number ], unique: true
      t.index %i[ printer_id batch ]
    end
  end
end
