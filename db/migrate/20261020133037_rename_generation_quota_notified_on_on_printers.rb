# The monthly allowance now counts print requests, not generations (decided on
# 20/10/2026). The column still says when the workshop was last told it had
# reached it.
class RenameGenerationQuotaNotifiedOnOnPrinters < ActiveRecord::Migration[8.1]
  def change
    rename_column :printers, :generation_quota_notified_on, :request_quota_notified_on
  end
end
