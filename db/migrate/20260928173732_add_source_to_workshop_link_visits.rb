class AddSourceToWorkshopLinkVisits < ActiveRecord::Migration[8.1]
  # Where a visit came from: the shop's plain link, its QR code, or one of the
  # named links it made (a flyer, a trade show). The count is now one row per
  # shop, day and source, so the old one-per-day index has to go.
  def change
    add_column :workshop_link_visits, :source, :string, null: false, default: "link"

    remove_index :workshop_link_visits, column: %i[ printer_id day ], unique: true
    add_index :workshop_link_visits, %i[ printer_id day source ], unique: true
  end
end
