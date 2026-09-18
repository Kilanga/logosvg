class CreatePrinters < ActiveRecord::Migration[8.1]
  def change
    create_table :printers do |t|
      # One shop per account: the workshop space shows exactly one listing.
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.string :name, null: false
      t.string :slug, null: false
      t.text :description

      # --- Where -------------------------------------------------------------
      t.string :address
      t.string :postal_code
      t.string :city
      # Filled by GeocodePrinterJob, never by the form.
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6

      # --- Contact -----------------------------------------------------------
      # Where print requests are sent. Distinct from the account's own address:
      # orders rarely land in the owner's personal inbox.
      t.string :orders_email, null: false
      t.string :phone
      t.string :website
      t.jsonb :opening_hours, null: false, default: {}

      # --- Lead times --------------------------------------------------------
      t.integer :response_time_hours
      t.integer :min_order_qty
      t.integer :standard_lead_days
      t.boolean :express_available, null: false, default: false
      t.integer :express_lead_hours

      # --- Delivery ----------------------------------------------------------
      t.boolean :ships, null: false, default: false
      t.string :shipping_zones, array: true, null: false, default: []
      t.integer :shipping_lead, comment: "Shipping lead time, in days"
      t.string :shipping_price_note
      t.boolean :pickup, null: false, default: false

      # --- Textile -----------------------------------------------------------
      t.boolean :provides_textile, null: false, default: false
      t.boolean :accepts_client_textile, null: false, default: false
      t.string :textile_brands, array: true, null: false, default: []
      t.integer :textile_label, null: false, default: 0

      # --- Printing ----------------------------------------------------------
      t.string :placements, array: true, null: false, default: []
      t.integer :max_print_width_cm
      t.integer :max_print_height_cm
      t.text :price_note

      # --- Listing -----------------------------------------------------------
      t.string :brand_color
      t.integer :status, null: false, default: 0
      # Set by the Atelier+ subscription in step 6, never by the printer.
      t.boolean :featured, null: false, default: false

      t.timestamps
    end

    add_index :printers, :slug, unique: true
    add_index :printers, :status
    add_index :printers, :featured
    add_index :printers, :postal_code
    add_index :printers, :city
    # The directory filters by area before anything else.
    add_index :printers, [ :latitude, :longitude ]
    # Shops that deliver across France stay visible outside the radius.
    add_index :printers, :ships
  end
end
