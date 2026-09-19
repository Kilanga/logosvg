# One row per shop per day, counting the people who arrived by its link or its
# QR code. Counted rather than logged: the figure is what an Atelier+ shop looks
# at, and keeping one row per visit would store personal data we have no use for.
class CreateWorkshopLinkVisits < ActiveRecord::Migration[8.1]
  def change
    create_table :workshop_link_visits do |t|
      t.references :printer, null: false, foreign_key: true
      t.date :day, null: false
      t.integer :count, null: false, default: 0

      t.timestamps
    end

    # Both the uniqueness the upsert relies on and the index the chart reads.
    add_index :workshop_link_visits, [ :printer_id, :day ], unique: true
  end
end
