module WorkshopLinksHelper
  # What a visit source is called on the statistics. `link` and `qr` are always
  # there; anything else is a channel the shop made, which may since have been
  # deleted — its visits stay counted, under the key it was printed with.
  def link_source_label(source, channels)
    case source
    when WorkshopLinkVisit::LINK then t("workshop.links.show.source_link")
    when WorkshopLinkVisit::QR then t("workshop.links.show.source_qr")
    else
      channel = channels.find { |candidate| candidate.key == source }
      channel ? channel.label : t("workshop.links.show.source_removed", key: source)
    end
  end

  # One bar per source, drawn as divs for the same reason as the daily chart.
  def source_bars(sources)
    peak = [ sources.values.max, 1 ].max

    sources.map { |source, count| { source: source, count: count, width: (count * 100.0 / peak).round } }
  end
end
