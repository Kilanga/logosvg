# A client belongs to one workshop, and only with that workshop's agreement.
#
# Decided on 09/10/2026: a client account is created from a workshop's link —
# the code on its poster or QR code admits them at once — or from the directory,
# as a request the workshop accepts or refuses in its space. Without that, any
# stranger could attach themselves to a shop and spend the generations of its
# plan. See docs/SPEC.md, "Rattachement d'un client à un atelier".
class AddWorkshopAffiliations < ActiveRecord::Migration[8.1]
  def change
    # The client's current workshop. Nil for every other role, and for a client
    # whose request has not been accepted yet: such an account can sign in but
    # cannot create anything.
    add_reference :users, :workshop, foreign_key: { to_table: :printers, on_delete: :nullify }

    # Every request and every admission, kept: the workshop's list of clients
    # comes from `users.workshop_id`, the history and the pending queue from here.
    create_table :client_affiliations do |t|
      t.references :client, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :printer, null: false, foreign_key: { on_delete: :cascade }
      t.integer :status, null: false, default: 0
      # How it began: the workshop's own code (admitted at once) or a request.
      t.integer :source, null: false, default: 0
      t.datetime :decided_at
      t.timestamps
    end

    # One open request per client at a time: asking another workshop replaces it.
    add_index :client_affiliations, :client_id, unique: true, where: "status = 0",
              name: "index_client_affiliations_one_pending_per_client"
    add_index :client_affiliations, %i[ printer_id status ]

    # The secret half of the poster's link. The slug is public — it is in the
    # directory's URLs — so the slug alone can only ever ask; the code admits.
    add_column :printers, :invite_code, :string
    add_index :printers, :invite_code, unique: true

    reversible do |direction|
      direction.up do
        select_values("SELECT id FROM printers").each do |id|
          execute "UPDATE printers SET invite_code = #{connection.quote(SecureRandom.alphanumeric(10).downcase)} WHERE id = #{id.to_i}"
        end
      end
    end
    change_column_null :printers, :invite_code, false
  end
end
