# What the client's dashboard shows: first what is waiting on them, then what
# has been happening.
#
# Gathered here rather than in the controller because "waiting on the client" is
# a business rule that will grow — designer proposals and versions to approve
# join it at step 8 — and because every list has to be loaded without an N+1.
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
      (failed_designs + unsent_designs + silent_print_requests).sort_by(&:on).reverse
    end

    # A generation that failed cost nothing: trying again is one click.
    def failed_designs
      designs.where(status: "failed").map do |design|
        Action.new(kind: :design_failed, record: design, on: design.updated_at)
      end
    end

    # A finished design nobody has been asked to print is the whole point of
    # the platform left undone.
    def unsent_designs
      designs.where(status: "ready")
             .where.missing(:print_requests)
             .map do |design|
        Action.new(kind: :design_unsent, record: design, on: design.updated_at)
      end
    end

    # The workshop has not even confirmed receipt. Worth saying so before the
    # sweep expires it.
    def silent_print_requests
      print_requests.awaiting_acknowledgement
                    .where(sent_at: ..reminder_mark)
                    .map do |print_request|
        Action.new(kind: :print_request_silent, record: print_request, on: print_request.sent_at)
      end
    end

    def reminder_mark
      Rails.application.config.tshirt.print_requests[:reminder_after_hours].hours.ago
    end

    def recent_designs
      designs.newest_first.limit(RECENT_LIMIT).includes(:printer).with_attached_print_file
    end

    def recent_print_requests
      print_requests.newest_first.limit(RECENT_LIMIT).includes(:printer, :design)
    end

    def designs = @client.designs.active

    def print_requests = @client.print_requests
end
