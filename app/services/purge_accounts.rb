# Deletes every account and everything accounts made: users, shops, designer
# profiles, designs, print requests, reviews, subscriptions, sessions, invites,
# visits, and the files attached to them. Written for one occasion: on
# 10/10/2026 the production database still held the demonstration accounts
# (whose password is in the public repository) and test accounts only.
#
# What is the platform's own stays: the review levels, the blocked terms (their
# author is forgotten), the Stripe event log.
#
# Run it once, and look first:
#
#   bin/rails data:purge_accounts            # counts
#   bin/rails data:purge_accounts CONFIRM=1  # deletes
#
# in the web container (`bin/kamal console`'s host, or `docker exec -it` on the
# server). Then create the administrator again: `bin/rails admin:create`.
class PurgeAccounts
  # In deletion order, children first. The foreign keys go round in circles
  # (designs ↔ reviews, users ↔ printers, printers → designer profiles): those
  # links are cut first. Not TRUNCATE: Postgres refuses it on `users` while
  # `blocked_terms` points there, even with nothing pointing.
  TABLES = %w[
    sessions generation_counters
    client_affiliations workshop_invites workshop_link_channels workshop_link_visits
    subscriptions printer_techniques
    designer_levels review_messages print_requests review_versions reviews designs
    printers designer_profiles users
  ].freeze

  CIRCULAR = {
    "designs" => %w[source_review_id parent_id root_id],
    "users" => %w[workshop_id],
    "printers" => %w[recommended_designer_profile_id]
  }.freeze

  MODELS = %w[User Printer DesignerProfile Design ReviewVersion PrintRequest].freeze

  def self.call(confirm: false, io: $stdout) = new(io:).call(confirm:)

  def initialize(io:)
    @io = io
  end

  def call(confirm:)
    counts = TABLES.index_with { |table| connection.select_value("SELECT COUNT(*) FROM #{connection.quote_table_name(table)}").to_i }
    report(counts, confirm:)
    delete! if confirm
    counts
  end

  private
    def connection = ActiveRecord::Base.connection

    def attachments = ActiveStorage::Attachment.where(record_type: MODELS)

    def report(counts, confirm:)
      @io.puts "Données liées à des comptes :"
      counts.each { |table, count| @io.puts format("  %-24s %d", table, count) }
      @io.puts format("  %-24s %d", "fichiers joints", attachments.count)
      @io.puts "Conservés : niveaux de vérification (#{ReviewLevel.count}), termes bloqués (#{BlockedTerm.count})."
      @io.puts(confirm ? "Suppression…" : "Rien n'est supprimé. Relancez avec CONFIRM=1 pour supprimer.")
    end

    def delete!
      blob_ids = attachments.distinct.pluck(:blob_id)

      ActiveRecord::Base.transaction do
        BlockedTerm.where.not(created_by_id: nil).update_all(created_by_id: nil)
        attachments.delete_all
        CIRCULAR.each do |table, columns|
          connection.execute("UPDATE #{table} SET #{columns.map { |column| "#{column} = NULL" }.join(', ')}")
        end
        TABLES.each { |table| connection.execute("DELETE FROM #{connection.quote_table_name(table)}") }
      end

      # The files last, once nothing points at them: a failure here leaves
      # orphan files on the volume, never a record without its file.
      ActiveStorage::Blob.where(id: blob_ids).strict_loading(false).find_each(&:purge)
      @io.puts "Terminé. Créez l'administrateur : bin/rails admin:create"
    end
end
