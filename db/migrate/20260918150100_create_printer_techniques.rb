class CreatePrinterTechniques < ActiveRecord::Migration[8.1]
  def change
    create_table :printer_techniques do |t|
      t.references :printer, null: false, foreign_key: true

      t.integer :technique, null: false
      # Required for screen printing, where every colour costs a screen. Left
      # empty by DTF and DTG, which have no colour ceiling.
      t.integer :max_colors
      t.string :accepted_formats, array: true, null: false, default: []

      t.timestamps
    end

    # One row per technique: a shop does not do screen printing twice.
    add_index :printer_techniques, [ :printer_id, :technique ], unique: true
    # The directory asks "who can print this design?" by technique first.
    add_index :printer_techniques, :technique
  end
end
