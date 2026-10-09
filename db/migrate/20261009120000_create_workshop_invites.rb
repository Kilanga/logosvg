# Single-use client sheets (decided on 09/10/2026). A workshop prints a batch of
# numbered sheets; each carries its own QR code, which admits one client, once.
# The number is the shop's follow-up: which sheet went to whom. See
# docs/SPEC.md, "Rattachement d'un client à un atelier".
class CreateWorkshopInvites < ActiveRecord::Migration[8.1]
  def change
    create_table :workshop_invites do |t|
      t.references :printer, null: false, foreign_key: { on_delete: :cascade }
      # Sheets prepared together, printed together.
      t.integer :batch, null: false
      # "Fiche n° 12": counted per shop, never reused.
      t.integer :number, null: false
      t.string :code, null: false
      t.references :used_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :used_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :workshop_invites, :code, unique: true
    add_index :workshop_invites, %i[ printer_id number ], unique: true
    add_index :workshop_invites, %i[ printer_id batch ]
  end
end
