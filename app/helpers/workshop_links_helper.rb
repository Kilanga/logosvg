module WorkshopLinksHelper
  # What a visit source is called on the statistics. `link` and `qr` are always
  # there; anything else is a channel the shop made, which may since have been
  # deleted — its visits stay counted, under the key it was printed with.
  def link_source_label(source, channels)
    case source
    when WorkshopLinkVisit::LINK then t("workshop.links.show.source_link")
    when WorkshopLinkVisit::QR then t("workshop.links.show.source_qr")
    when WorkshopLinkVisit::EMAIL then t("workshop.links.show.source_email")
    else
      channel = channels.find { |candidate| candidate.key == source }
      channel ? channel.label : t("workshop.links.show.source_removed", key: source)
    end
  end

  # The shop's name on its poster is set as big as it allows: a short name
  # fills the flat of colour, a long one — or one long word — still fits beside
  # the QR code. Written out whole, so Tailwind finds the classes: the most
  # characters, the longest word, the class.
  POSTER_NAME_SIZES = [
    [ 12, 8, "text-[112px]" ],
    [ 20, 11, "text-[84px]" ],
    [ 32, 14, "text-[64px]" ]
  ].freeze

  def poster_name_size(name)
    name = name.to_s
    longest_word = name.split.map(&:length).max.to_i
    POSTER_NAME_SIZES.find { |total, word, _| name.length <= total && longest_word <= word }&.last || "text-[48px]"
  end

  # How a client came to the shop, for its list of clients: the support whose
  # link they followed, a request, or — for the rows made before the channel
  # was kept — the numbered sheet or « link or poster ».
  def admission_label(affiliation, channels)
    return t("workshop.links.show.source_sheet") if affiliation.from_sheet?
    return link_source_label(affiliation.channel, channels) if affiliation.channel.present?
    return t("workshop.links.show.source_request") if affiliation.from_request?

    t("workshop.links.show.source_unknown")
  end

  # One bar per source, drawn as divs for the same reason as the daily chart.
  def source_bars(sources)
    peak = [ sources.values.max, 1 ].max

    sources.map { |source, count| { source: source, count: count, width: (count * 100.0 / peak).round } }
  end
end
