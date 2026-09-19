module PrintRequestsHelper
  # The statuses a request walks through, in order. Drawn as a rail rather than
  # written as a word: a client wants to know where the job is, not to read a
  # noun. Cancelled and expired are not on it — they are ends, not steps.
  TIMELINE = %w[ sent acknowledged quoted in_production completed ].freeze

  def print_request_status_pill(print_request)
    style = case print_request.status
    when "completed" then "pill-success"
    when "canceled", "expired" then "pill-warning"
    else "border border-line text-muted"
    end

    tag.span t("enums.print_request.status.#{print_request.status}"), class: "pill #{style}"
  end

  # Each step with whether it has been reached, so the view can draw the rail
  # without working out the order itself.
  def print_request_timeline(print_request)
    return [] unless print_request.open? || print_request.completed?

    reached = TIMELINE.index(print_request.status).to_i

    TIMELINE.each_with_index.map do |status, index|
      { status: status,
        label: t("enums.print_request.status.#{status}"),
        reached: index <= reached,
        current: index == reached }
    end
  end

  # "M × 10, L × 5" — the order as a workshop reads it.
  def sizes_summary(print_request)
    print_request.ordered_sizes.map { |size, quantity| "#{size} × #{quantity}" }.join("   ")
  end

  # A short, human reference for an email subject or a counter slip. The token
  # itself is long on purpose; eight characters are enough to talk about.
  def print_request_reference(print_request) = print_request.token.first(8).upcase
end
