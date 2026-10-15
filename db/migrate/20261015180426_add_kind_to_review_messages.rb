# What a message is, beyond its words (reported on 15/10/2026): a request for
# another go and a dispute read like ordinary messages in the conversation.
class AddKindToReviewMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :review_messages, :kind, :string, null: false, default: "message"
    add_check_constraint :review_messages, "kind IN ('message', 'revision', 'dispute', 'fix')",
                         name: "review_messages_kind_known"
  end
end
