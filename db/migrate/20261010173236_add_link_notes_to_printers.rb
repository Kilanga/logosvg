# The shop's own words on its poster and in the email it sends a client
# (decided on 10/10/2026). Optional, saved once in « Mon lien », reused on
# every print and every email. Short on purpose: the poster's text sits under
# the shop's name, on its flat of colour.
class AddLinkNotesToPrinters < ActiveRecord::Migration[8.1]
  def change
    add_column :printers, :poster_note, :string, limit: 140
    add_column :printers, :link_email_note, :string, limit: 400
  end
end
