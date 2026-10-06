# The variants born of one click share this token: together they cost one
# reprise, not three. Until now only the generation service knew which images
# went together, and it forgets everything each time its machine is switched
# off — the lineage's count now lives here too. See Design#refinements_used.
class AddBatchTokenToDesigns < ActiveRecord::Migration[8.1]
  def change
    add_column :designs, :batch_token, :string
  end
end
