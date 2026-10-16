# Every amount the site shows, emails included: euros, the number before the
# sign, French separators. One place, rather than number_to_currency spelled
# out ten times with its options (revue du 16/10/2026).
module MoneyHelper
  def money(cents, precision: 2) = number_to_currency((cents || 0) / 100.0, unit: "€", format: "%n %u", precision: precision)
end
