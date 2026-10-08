# A design the client brought ready-made (mode "upload") is marked as AI only
# when the client says so: the platform did not draw it, and it does not get to
# label someone's own drawing as a machine's.
class AddAiDeclaredToDesigns < ActiveRecord::Migration[8.1]
  def change
    add_column :designs, :ai_declared, :boolean, null: false, default: false
  end
end
