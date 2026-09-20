# Every webhook Stripe sends is recorded before it is acted on, so that a
# retried delivery — which Stripe does freely — can never be processed twice.
class CreateStripeEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :stripe_events do |t|
      t.string :stripe_id, null: false
      t.string :event_type, null: false
      t.datetime :processed_at
      t.text :error_message

      t.timestamps
    end

    # The whole point of the table: one row per Stripe event id, ever.
    add_index :stripe_events, :stripe_id, unique: true
    add_index :stripe_events, :event_type
  end
end
