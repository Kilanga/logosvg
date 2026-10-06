# What the client's dashboard shows: first what is waiting on them, then what
# has been happening.
#
# Gathered here rather than in the controller because "waiting on the client" is
# a business rule that keeps growing, and because every list has to be loaded
# without an N+1.
class ClientDashboard
  # One pending action, whatever kind it is. `kind` names the sentence to show;
  # where acting on it happens is the view's business, not this object's — a
  # service that builds URLs needs a request to exist before it can be called.
  Action = Data.define(:kind, :record, :on)

  RECENT_LIMIT = 6

  def self.call(...) = new(...).call

  def initialize(client:)
    @client = client
  end

  def call = { actions: actions, designs: recent_designs, print_requests: recent_print_requests }

  private
    def actions
      (failed_designs + unsent_designs + silent_print_requests +
       delivered_reviews + review_proposals).sort_by(&:on).reverse
    end

    # A generation that failed cost nothing: trying again is one click. A
    # failed proposal is not news while another of its click came through, and
    # a click that failed whole is said once.
    def failed_designs
      came_through = designs.where.not(status: "failed").where.not(batch_token: nil).select(:batch_token)
      failed = designs.where(status: "failed")
      failed.where(batch_token: nil).or(failed.where.not(batch_token: came_through))
            .to_a.uniq { |design| design.batch_token || design.token }.map do |design|
        Action.new(kind: :design_failed, record: design, on: design.updated_at)
      end
    end

    # A finished design nobody has been asked to print is the whole point of
    # the platform left undone.
    def unsent_designs
      designs.kept.where(status: "ready")
             .where.missing(:print_requests)
             .map do |design|
        Action.new(kind: :design_unsent, record: design, on: design.updated_at)
      end
    end

    # The workshop has not even confirmed receipt. Worth saying so before the
    # sweep expires it.
    #
    # `includes(:printer)`: the view names the shop in this sentence. Missed
    # here, and `strict_loading_by_default` never catches it in development —
    # a record reached through `Current.user`'s own associations inherits
    # `Current.user`'s own loaded-by-`includes` state instead of the global
    # default, so this exact N+1 ran silently under the safety net meant to
    # catch it. Caught instead by counting queries: see
    # `query_budget_test.rb`, "the client dashboard stays flat".
    def silent_print_requests
      print_requests.awaiting_acknowledgement
                    .where(sent_at: ..reminder_mark)
                    .includes(:printer)
                    .map do |print_request|
        Action.new(kind: :print_request_silent, record: print_request, on: print_request.sent_at)
      end
    end

    def reminder_mark
      Rails.application.config.tshirt.print_requests[:reminder_after_hours].hours.ago
    end

    # Paid for and done: validating it is the one step left.
    def delivered_reviews
      reviews.where(status: "delivered").includes(:design).map do |review|
        Action.new(kind: :review_delivered, record: review, on: review.delivered_at)
      end
    end

    # The one pending action with its own deadline: past it, the sweep answers
    # for the client. `proposal_open?` is the model's own rule, not re-derived
    # here — see docs/SPEC.md, "Espace client".
    def review_proposals
      reviews.where(status: "returned_to_client").includes(:design)
             .select(&:proposal_open?).map do |review|
        Action.new(kind: :review_proposal, record: review, on: review.returned_at)
      end
    end

    def recent_designs
      designs.newest_first.limit(RECENT_LIMIT).includes(:printer).with_attached_print_file
    end

    def recent_print_requests
      print_requests.newest_first.limit(RECENT_LIMIT).includes(:printer, :design)
    end

    def designs = @client.designs.active

    def print_requests = @client.print_requests

    def reviews = @client.reviews
end
