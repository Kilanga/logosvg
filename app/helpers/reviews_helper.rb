module ReviewsHelper
  def review_status_pill(review)
    style = case review.status
    when "accepted" then "pill-success"
    when "canceled", "returned_to_client" then "pill-warning"
    when "delivered" then "border border-emulsion text-emulsion"
    else "border border-line text-muted"
    end

    tag.span t("enums.review.status.#{review.status}"), class: "pill #{style}"
  end

  # Red under six hours, as the spec asks: it is the designer's own deadline,
  # and it is the one number they scan the queue for.
  def due_badge(review)
    return nil if review.due_at.blank?

    tone = if review.overdue? then "text-warning"
    elsif review.due_soon? then "text-warning"
    else "text-muted"
    end

    tag.span t("reviews.due", when: distance_of_time_in_words_to_now(review.due_at)),
             class: "label-rule #{tone}"
  end

  def money(cents) = number_to_currency((cents || 0) / 100.0, unit: "€", format: "%n %u")

  # "+30 €" or "−30 €", with the sign that tells a client which way it goes.
  def signed_money(cents)
    return money(0) if cents.to_i.zero?

    prefix = cents.positive? ? "+" : "−"
    "#{prefix}#{money(cents.abs)}"
  end

  # What the inspection found, in words rather than as a raw hash.
  def version_checks(version)
    checks = version.checks

    if version.vector?
      [ t("reviews.checks.inks", count: version.inks_count.to_i) ]
    else
      [
        ("#{checks['width_px']} × #{checks['height_px']} px" if checks["width_px"]),
        ("#{checks['dpi']} dpi" if checks["dpi"]),
        (t("reviews.checks.transparent") if checks["has_alpha"])
      ].compact
    end
  end

  def version_warnings(version)
    Array(version.checks["warnings"]).map { |w| t("reviews.warnings.#{w}") }
  end
end
