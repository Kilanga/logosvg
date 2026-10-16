module ReviewsHelper
  BriefFields = Struct.new(*Review::BRIEF_KEYS.map(&:to_sym))

  # What `fields_for :brief` reads the four points from: the brief is a hash
  # in the database, and a form builder wants methods.
  def brief_fields(review) = BriefFields.new(*Review::BRIEF_KEYS.map { |key| review.brief[key] })

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
  # Only while the work is the designer's to do (reported on 15/10/2026: still
  # « Échéance 2 jours » once delivered, or finished).
  def due_badge(review)
    return nil if review.due_at.blank? || !review.in_progress?

    tone = if review.overdue? then "text-warning"
    elsif review.due_soon? then "text-warning"
    else "text-muted"
    end

    tag.span t("reviews.due", when: distance_of_time_in_words_to_now(review.due_at)),
             class: "label-rule #{tone}"
  end

  # What the designer gets from this review, as it stands: the share on offer
  # while it is open, what was actually paid once it is settled — less after a
  # split, the guaranteed share after a closure, nothing otherwise.
  def designer_earnings_cents(review)
    case review.status
    when "accepted" then review.payout_cents
    when "canceled" then review.designer_payout_cents.to_i
    else review.designer_share_cents
    end
  end

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
