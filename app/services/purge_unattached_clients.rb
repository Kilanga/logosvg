# Deletes the client accounts that belong to no workshop, with everything they
# made. Written for one occasion: on 09/10/2026 a client account started needing
# a workshop, and every client account created before was a test account.
#
# Run it once, and look first:
#
#   bin/kamal app exec "bin/rails clients:purge_unattached"            # lists
#   bin/kamal app exec "bin/rails clients:purge_unattached CONFIRM=1"  # deletes
#
# A client waiting on a workshop's answer is kept: that account is new, not a
# leftover. A design, an order or a review is deleted with its client, with its
# files — test data, never a real order. Not a job, not scheduled: the day real
# clients exist, an account without a shop is one a shop let go, and deleting it
# would be wrong.
class PurgeUnattachedClients
  Summary = Data.define(:clients, :designs, :print_requests, :reviews)

  def self.call(confirm: false, io: $stdout) = new(io:).call(confirm:)

  def initialize(io:)
    @io = io
  end

  def call(confirm:)
    summary = summarise
    report(summary, confirm:)
    delete! if confirm && summary.clients.any?
    summary
  end

  private
    def client_ids
      @client_ids ||= User.client.where(workshop_id: nil)
                          .where.not(id: ClientAffiliation.pending.select(:client_id))
                          .pluck(:id)
    end

    def design_ids = @design_ids ||= Design.where(user_id: client_ids).pluck(:id)

    def review_ids
      @review_ids ||= Review.where(client_id: client_ids).or(Review.where(design_id: design_ids)).pluck(:id)
    end

    def print_request_ids
      @print_request_ids ||= PrintRequest.where(client_id: client_ids)
                                         .or(PrintRequest.where(design_id: design_ids)).pluck(:id)
    end

    def summarise
      Summary.new(clients: User.where(id: client_ids).order(:created_at).pluck(:email_address),
                  designs: design_ids.size, print_requests: print_request_ids.size,
                  reviews: review_ids.size)
    end

    def report(summary, confirm:)
      @io.puts "Comptes clients sans atelier : #{summary.clients.size}"
      summary.clients.each { |email| @io.puts "  #{email}" }
      @io.puts "Avec eux : #{summary.designs} designs, #{summary.print_requests} demandes, " \
               "#{summary.reviews} vérifications."
      @io.puts(confirm ? "Suppression…" : "Rien n'est supprimé. Relancez avec CONFIRM=1 pour supprimer.")
    end

    # Children before parents, references cut before the rows they point to:
    # the foreign keys are not cascading, and must not be loosened for this.
    def delete!
      ActiveRecord::Base.transaction do
        PrintRequest.where(id: print_request_ids).find_each(&:destroy!)

        designs = Design.where(id: design_ids)
        designs.update_all(source_review_id: nil, parent_id: nil, root_id: nil)
        # Another client's design made from one of these reviews keeps its file
        # and loses only the link back.
        Design.where(source_review_id: review_ids).update_all(source_review_id: nil)

        Review.where(id: review_ids).find_each(&:destroy!)
        designs.find_each(&:destroy!)

        GenerationCounter.where(user_id: client_ids).delete_all
        User.where(id: client_ids).find_each(&:destroy!)
      end
      @io.puts "Terminé."
    end
end
