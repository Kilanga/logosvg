# How many people arrived by a shop's link or QR code, by day.
#
# Counted, not logged: the figure is what an Atelier+ shop looks at, and one
# row per visitor would store personal data nobody needs.
class WorkshopLinkVisit < ApplicationRecord
  belongs_to :printer

  # Atomic: a poster on a busy counter can be scanned by several people in the
  # same second, and find-then-increment would lose some of them.
  def self.record!(printer)
    upsert(
      { printer_id: printer.id, day: Time.zone.today, count: 1,
        created_at: Time.current, updated_at: Time.current },
      unique_by: %i[ printer_id day ],
      on_duplicate: Arel.sql("count = workshop_link_visits.count + 1, updated_at = EXCLUDED.updated_at")
    )
  end

  # The last `days` days, oldest first, with the empty ones filled in: a chart
  # with holes in it reads as "no data", not as "no visitors".
  def self.series(printer, days:)
    counted = where(printer: printer)
              .where(day: (days - 1).days.ago.to_date..Time.zone.today)
              .pluck(:day, :count).to_h

    ((days - 1).days.ago.to_date..Time.zone.today).map { |day| [ day, counted[day].to_i ] }
  end
end
