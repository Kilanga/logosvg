class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      t.references :printer, null: false, foreign_key: true, index: { unique: true }

      t.string :plan, null: false, default: "listing"
      t.string :status, null: false, default: "incomplete"

      # Stripe's own identifiers. The customer outlives any one subscription,
      # so it is kept even after a cancellation: resubscribing must not create
      # a second customer and lose the invoice history.
      t.string :stripe_customer_id
      t.string :stripe_subscription_id

      t.datetime :current_period_end
      # When the payment first failed. The listing stays visible for a few days
      # from here, not from the moment the sweep happens to notice.
      t.datetime :past_due_since
      t.datetime :canceled_at

      t.timestamps
    end

    add_index :subscriptions, :stripe_customer_id
    add_index :subscriptions, :stripe_subscription_id, unique: true
    # The directory asks "is this shop visible?" on every listing it shows.
    add_index :subscriptions, [ :status, :past_due_since ]
  end
end
