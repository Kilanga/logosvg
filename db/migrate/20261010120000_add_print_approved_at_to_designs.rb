# When the client looked at what the workshop will print and said yes. Asked
# only of a client's own picture put in format (mode "upload"): the technique
# changes it — flattened into a few inks, or kept in full colour at 300 dpi — and
# the client must see that before a workshop does. Decided on 10/10/2026.
class AddPrintApprovedAtToDesigns < ActiveRecord::Migration[8.1]
  def change
    add_column :designs, :print_approved_at, :datetime
  end
end
