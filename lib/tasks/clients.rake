namespace :clients do
  desc "Liste les comptes clients rattachés à aucun atelier ; CONFIRM=1 les supprime avec leurs données"
  task purge_unattached: :environment do
    PurgeUnattachedClients.call(confirm: ENV["CONFIRM"] == "1")
  end
end
