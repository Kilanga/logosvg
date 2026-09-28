class CreateWorkshopLinkChannels < ActiveRecord::Migration[8.1]
  # A named way of sharing the shop's link: "flyer", "salon de Rennes". The key
  # is what travels in the URL and never changes once printed; the label is what
  # the shop reads.
  def change
    create_table :workshop_link_channels do |t|
      t.references :printer, null: false, foreign_key: true, index: false
      t.string :key, null: false
      t.string :label, null: false

      t.timestamps
    end

    add_index :workshop_link_channels, %i[ printer_id key ], unique: true
  end
end
