# How many people arrived by a shop's link or QR code, by day and by source.
#
# Counted, not logged: the figure is what an Atelier+ shop looks at, and one
# row per visitor would store personal data nobody needs.
class WorkshopLinkVisit < ApplicationRecord
  # The plain address, the QR code printed on the poster, and the link in the
  # email a shop sends a client. Anything else is the key of one of the shop's
  # own `WorkshopLinkChannel`s.
  LINK = "link".freeze
  QR = "qr".freeze
  EMAIL = "email".freeze
  BUILT_IN = [ LINK, QR, EMAIL ].freeze

  belongs_to :printer

  # Atomic: a poster on a busy counter can be scanned by several people in the
  # same second, and find-then-increment would lose some of them.
  def self.record!(printer, source: LINK)
    upsert(
      { printer_id: printer.id, day: Time.zone.today, source: source, count: 1,
        created_at: Time.current, updated_at: Time.current },
      unique_by: %i[ printer_id day source ],
      on_duplicate: Arel.sql("count = workshop_link_visits.count + 1, updated_at = EXCLUDED.updated_at")
    )
  end

  # The last `days` days, oldest first, with the empty ones filled in: a chart
  # with holes in it reads as "no data", not as "no visitors". Every source
  # added up — the chart asks how many came, not how.
  def self.series(printer, days:)
    counted = where(printer: printer)
              .where(day: (days - 1).days.ago.to_date..Time.zone.today)
              .group(:day).sum(:count)

    ((days - 1).days.ago.to_date..Time.zone.today).map { |day| [ day, counted[day].to_i ] }
  end

  # `{ "qr" => 12, "flyer" => 5 }` over the last `days` days, busiest first.
  def self.by_source(printer, days:)
    where(printer: printer)
      .where(day: (days - 1).days.ago.to_date..Time.zone.today)
      .group(:source).sum(:count)
      .sort_by { |source, count| [ -count, source ] }.to_h
  end
end
