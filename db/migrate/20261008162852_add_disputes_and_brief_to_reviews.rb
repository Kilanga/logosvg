# Decided on 08/10/2026: the client can say a delivery does not do what was
# asked, an administrator can split the money, and the brief is structured so
# that "what was asked" can be checked point by point.
class AddDisputesAndBriefToReviews < ActiveRecord::Migration[8.1]
  def change
    change_table :reviews, bulk: true do |t|
      # The structured brief: what must change, what must stay, the exact text
      # to print, the imposed colours. `client_brief` stays, composed from it,
      # for everything that already reads it.
      t.jsonb :brief, null: false, default: {}

      t.datetime :disputed_at
      t.string :dispute_reason
      t.text :dispute_message
      t.datetime :fix_offered_at

      # Reminders before the automatic acceptance, counted per delivery.
      t.integer :acceptance_reminders_sent, null: false, default: 0

      # What the designer is paid when an administrator splits the money. Nil
      # means the full share.
      t.integer :designer_payout_cents
    end
    add_index :reviews, :disputed_at

    # What the designer says they covered, point by point, on each version.
    add_column :review_versions, :brief_coverage, :jsonb, null: false, default: {}
  end
end
