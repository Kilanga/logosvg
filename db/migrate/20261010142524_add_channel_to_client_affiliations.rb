# Which way a client came in (decided on 10/10/2026): the poster's QR code, the
# plain link, the email the shop sent, or one of its named links. The same
# values as `workshop_link_visits.source`. Empty for a client who found the
# shop in the directory, and for everyone admitted before this column.
class AddChannelToClientAffiliations < ActiveRecord::Migration[8.1]
  def change
    add_column :client_affiliations, :channel, :string, limit: 40
  end
end
