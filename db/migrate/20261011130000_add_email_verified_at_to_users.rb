# Décidé le 11/10/2026 : une adresse email se vérifie avant que le compte ne
# puisse générer, envoyer, payer ou s'abonner. Les comptes déjà ouverts
# (l'administrateur, les comptes de recette) sont tenus pour vérifiés : ils ont
# été créés à la main ou avant que la règle existe.
class AddEmailVerifiedAtToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :email_verified_at, :datetime
    execute "UPDATE users SET email_verified_at = created_at"
  end

  def down
    remove_column :users, :email_verified_at
  end
end
