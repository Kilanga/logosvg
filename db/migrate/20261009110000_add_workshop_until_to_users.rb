# A client's place with a workshop lasts `clients.attachment_days` from the day
# they were admitted (decided on 09/10/2026), after which they scan the shop's
# link or QR code again, or ask it again. See docs/SPEC.md, "Rattachement d'un
# client à un atelier".
class AddWorkshopUntilToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :workshop_until, :datetime
    # Whoever is attached today starts their thirty days now.
    execute <<~SQL
      UPDATE users SET workshop_until = NOW() + INTERVAL '30 days' WHERE workshop_id IS NOT NULL
    SQL
  end

  def down
    remove_column :users, :workshop_until
  end
end
