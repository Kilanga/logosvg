# How many emails the site handed to Brevo each day, and how many it could not
# deliver at all (decided on 10/10/2026). The free Brevo plan stops at 300 a
# day, counted per recipient, every email of the site included: the
# administration watches the figure, rather than learning from a client that a
# password reset never came.
class CreateMailDeliveryDays < ActiveRecord::Migration[8.1]
  def change
    create_table :mail_delivery_days do |t|
      t.date :day, null: false
      t.integer :recipients_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.timestamps
    end

    add_index :mail_delivery_days, :day, unique: true
  end
end
