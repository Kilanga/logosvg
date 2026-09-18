# A shop does not merely "practise DTF": it practises DTF *its own way* — under
# its own name, delivering the file format its machine expects, in the colour
# space its workflow uses. The technique key stays the mode the client chooses;
# everything behind it belongs to the printer.
#
# `technique` becomes a string holding a catalogue key rather than a Rails enum:
# the catalogue lives in the microservice, and duplicating its list here is what
# the spec forbids.
class RedefinePrinterTechniques < ActiveRecord::Migration[8.1]
  def up
    add_column :printer_techniques, :technique_key, :string

    # The former enum, in its declared order.
    execute(<<~SQL)
      UPDATE printer_techniques SET technique_key = CASE technique
        WHEN 0 THEN 'screen_printing'
        WHEN 1 THEN 'dtf'
        WHEN 2 THEN 'dtg'
        WHEN 3 THEN 'flex'
        WHEN 4 THEN 'embroidery'
      END
    SQL

    remove_index :printer_techniques, :technique
    remove_index :printer_techniques, [ :printer_id, :technique ]
    remove_column :printer_techniques, :technique
    rename_column :printer_techniques, :technique_key, :technique
    change_column_null :printer_techniques, :technique, false

    # Formats are no longer a list the shop accepts: it names the one file it
    # wants, and compatibility is judged on the technique.
    remove_column :printer_techniques, :accepted_formats

    # The printer's own wording — "flocage 1 couleur", "impression photo". Blank
    # falls back to the catalogue's French label.
    add_column :printer_techniques, :label, :string

    # What this shop's machine expects for this technique. Two shops doing
    # sublimation may want different files.
    add_column :printer_techniques, :output_format, :string, null: false, default: "svg"
    add_column :printer_techniques, :color_space, :string, null: false, default: "rgb"

    # The one technique kept when a client answers "I don't know".
    add_column :printer_techniques, :primary, :boolean, null: false, default: false

    # Blank falls back to the shop-wide maximum on the listing.
    add_column :printer_techniques, :max_print_width_cm, :integer
    add_column :printer_techniques, :max_print_height_cm, :integer

    add_column :printer_techniques, :note, :string

    add_index :printer_techniques, :technique
    add_index :printer_techniques, [ :printer_id, :technique ], unique: true
    # At most one primary per shop, enforced by the database and not only by a
    # validation that a concurrent write could slip past.
    add_index :printer_techniques, :printer_id, unique: true,
              where: '"primary" = true', name: "index_printer_techniques_on_single_primary"
  end

  def down
    remove_index :printer_techniques, name: "index_printer_techniques_on_single_primary"
    remove_index :printer_techniques, [ :printer_id, :technique ]
    remove_index :printer_techniques, :technique

    remove_column :printer_techniques, :label
    remove_column :printer_techniques, :output_format
    remove_column :printer_techniques, :color_space
    remove_column :printer_techniques, :primary
    remove_column :printer_techniques, :max_print_width_cm
    remove_column :printer_techniques, :max_print_height_cm
    remove_column :printer_techniques, :note

    add_column :printer_techniques, :accepted_formats, :string, array: true, null: false, default: []

    rename_column :printer_techniques, :technique, :technique_key
    add_column :printer_techniques, :technique, :integer

    execute(<<~SQL)
      UPDATE printer_techniques SET technique = CASE technique_key
        WHEN 'screen_printing' THEN 0
        WHEN 'dtf' THEN 1
        WHEN 'dtg' THEN 2
        WHEN 'flex' THEN 3
        WHEN 'embroidery' THEN 4
      END
    SQL

    change_column_null :printer_techniques, :technique, false
    remove_column :printer_techniques, :technique_key

    add_index :printer_techniques, :technique
    add_index :printer_techniques, [ :printer_id, :technique ], unique: true
  end
end
