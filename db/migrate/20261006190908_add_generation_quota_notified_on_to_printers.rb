# The month a workshop was last told it had used its plan's generations. One
# email per month, not one per refused client.
class AddGenerationQuotaNotifiedOnToPrinters < ActiveRecord::Migration[8.1]
  def change
    add_column :printers, :generation_quota_notified_on, :date
  end
end
