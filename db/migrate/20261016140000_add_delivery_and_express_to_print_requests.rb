# What the client chose among what the shop offers (decided on 16/10/2026):
# picking the order up or having it sent, and the express turnaround. Nil for
# requests sent before, and for a shop that declares neither way.
class AddDeliveryAndExpressToPrintRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :print_requests, :delivery_method, :string
    add_column :print_requests, :express, :boolean, default: false, null: false
  end
end
