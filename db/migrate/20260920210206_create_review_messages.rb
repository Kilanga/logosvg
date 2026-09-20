# The conversation between a client and their designer. Read by both of them
# and by an administrator settling a dispute.
class CreateReviewMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :review_messages do |t|
      t.references :review, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.datetime :read_at

      t.timestamps
    end

    # The thread, in order, and the unread count beside it.
    add_index :review_messages, [ :review_id, :created_at ]
    add_index :review_messages, [ :review_id, :read_at ]
  end
end
