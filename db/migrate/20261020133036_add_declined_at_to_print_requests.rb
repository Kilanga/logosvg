# A workshop can now set a request aside as not worth quoting (decided on
# 20/10/2026): the moment it did so is kept, like the other steps.
class AddDeclinedAtToPrintRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :print_requests, :declined_at, :datetime
  end
end
