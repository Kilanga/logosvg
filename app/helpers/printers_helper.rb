module PrintersHelper
  # What the map controller needs, and nothing more. Built here rather than in
  # the view so the payload stays small and its shape is obvious.
  def map_points(printers)
    printers.map do |printer|
      {
        name: printer.name,
        city: printer.city,
        url: printer_path(printer),
        latitude: printer.latitude.to_f,
        longitude: printer.longitude.to_f,
        featured: printer.featured?
      }
    end
  end

  # "Sérigraphie, 4 encres max, 30 × 40 cm" — the one line that tells a client
  # whether their design can be printed here. The shop's own wording leads; the
  # limits follow, because they are what actually decides.
  def technique_summary(technique)
    [
      technique.display_label,
      technique_ink_limit(technique),
      technique_size_limit(technique)
    ].compact_blank.join(", ")
  end

  def technique_ink_limit(technique)
    if technique.limited_colors?
      t("printers.ink_ceiling", count: technique.max_colors)
    else
      t("printers.unlimited_colors")
    end
  end

  def technique_size_limit(technique)
    width = technique.effective_max_width_cm
    height = technique.effective_max_height_cm
    "#{width} × #{height} cm" if width.present? && height.present?
  end

  # What the shop actually hands over, in the terms a print shop uses. Shown on
  # the listing because two shops doing the same technique may not want the same
  # file — and the client's preview will follow this.
  def technique_delivery(technique)
    t("printers.delivery",
      file_format: technique.output_format.upcase,
      color_space: t("enums.printer_technique.color_space.#{technique.color_space}"))
  end

  # Characteristics grouped the way a client reads them: what gets printed, on
  # what, and how it arrives. Built here rather than in the template because
  # each row is a small decision, and a view full of inline conditionals is a
  # view nobody dares change.
  def printer_characteristics(printer)
    {
      printing: [
        [ t("activerecord.attributes.printer.placements"),
          printer.placements.map { |p| t("enums.printer.placements.#{p}") }.to_sentence ],
        [ t("public.printers.characteristics.max_size"), print_area(printer) ],
        [ t("activerecord.attributes.printer.min_order_qty"), quantity(printer.min_order_qty) ],
        [ t("activerecord.attributes.printer.price_note"), printer.price_note ]
      ],
      textile: [
        [ t("public.printers.characteristics.textile_source"), textile_source(printer) ],
        [ t("activerecord.attributes.printer.textile_brands"), printer.textile_brands.to_sentence ],
        [ t("activerecord.attributes.printer.textile_label"), textile_label(printer) ]
      ],
      delivery: [
        [ t("activerecord.attributes.printer.standard_lead_days"),
          duration_in_days(printer.standard_lead_days) ],
        [ t("activerecord.attributes.printer.express_available"), express(printer) ],
        [ t("activerecord.attributes.printer.shipping_zones"), shipping_zones(printer) ],
        [ t("activerecord.attributes.printer.shipping_lead"),
          duration_in_days(printer.shipping_lead) ],
        [ t("activerecord.attributes.printer.shipping_price_note"), printer.shipping_price_note ],
        [ t("activerecord.attributes.printer.pickup"), (t("printers.yes") if printer.pickup?) ]
      ]
    }
  end

  def printer_status_pill(printer)
    style = case printer.status
    when "published" then "pill-success"
    when "suspended" then "pill-warning"
    else "border border-line text-muted"
    end

    tag.span t("enums.printer.status.#{printer.status}"), class: "pill #{style}"
  end

  private
    def print_area(printer)
      width = printer.max_print_width_cm
      height = printer.max_print_height_cm
      "#{width} × #{height} cm" if width.present? && height.present?
    end

    def quantity(count) = (t("printers.pieces", count: count) if count.present?)

    def duration_in_days(count) = (t("printers.days", count: count) if count.present?)

    def textile_source(printer)
      [
        (t("printers.textile_provided") if printer.provides_textile?),
        (t("printers.textile_accepted") if printer.accepts_client_textile?)
      ].compact.to_sentence
    end

    def textile_label(printer)
      t("enums.printer.textile_label.#{printer.textile_label}") unless printer.label_none?
    end

    def express(printer)
      return unless printer.express_available?

      if printer.express_lead_hours.present?
        t("printers.hours", count: printer.express_lead_hours)
      else
        t("printers.yes")
      end
    end

    def shipping_zones(printer)
      return unless printer.ships?

      printer.shipping_zones.map { |zone| t("enums.printer.shipping_zones.#{zone}") }.to_sentence
    end
end
