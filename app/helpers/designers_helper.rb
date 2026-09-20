module DesignersHelper
  def designer_status_pill(profile)
    style = case profile.status
    when "active" then "pill-success"
    when "suspended" then "pill-warning"
    else "border border-line text-muted"
    end

    tag.span t("enums.designer_profile.status.#{profile.status}"), class: "pill #{style}"
  end

  # A level with no price is quoted case by case; saying "0 €" would be a lie.
  def level_price(level)
    return t("designers.levels.quoted") if level.quoted?

    number_to_currency(level.price_euros, unit: "€", format: "%n %u", precision: 0)
  end

  # "48 h, 1 retour inclus" — the two things that decide whether a designer
  # signs up for a level.
  def level_terms(level)
    [ t("designers.levels.turnaround", count: level.turnaround_hours),
      t("designers.levels.revisions", count: level.revisions_included) ].join(" · ")
  end

  # Whether this designer can be given work, and if not, why — in their own
  # terms rather than as a status name.
  def availability_note(profile)
    return t("designers.available") if profile.can_take_work?

    t("designers.unavailable.#{profile.unavailable_reason}")
  end

  def rating_summary(profile)
    return t("designers.no_rating") unless profile.rated?

    t("designers.rating", score: number_with_precision(profile.rating_avg, precision: 1),
                          count: profile.ratings_count)
  end
end
