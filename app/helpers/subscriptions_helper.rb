module SubscriptionsHelper
  def subscription_status_pill(subscription)
    style = case subscription.status
    when "active", "trialing" then "pill-success"
    when "past_due" then "pill-warning"
    else "border border-line text-muted"
    end

    tag.span t("enums.subscription.status.#{subscription.status}"), class: "pill #{style}"
  end

  # A bar chart drawn as divs rather than pulled from a charting library: it is
  # thirty numbers, it must print, and it must not cost a JavaScript dependency.
  def visit_bars(series)
    peak = [ series.map(&:last).max, 1 ].max

    series.map do |day, count|
      { day: day, count: count, height: (count * 100.0 / peak).round }
    end
  end
end
