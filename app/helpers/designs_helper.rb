module DesignsHelper
  # The technique under the name the shop in context gives it, falling back to
  # the catalogue's. A client who arrived by a workshop's link should read that
  # workshop's words.
  def workshop_technique_label(entry)
    context_printer&.technique_for(entry.key)&.display_label || entry.label
  end

  def technique_family_hint(entry)
    t("designs.family_hint.#{entry.family}")
  end

  # The sizes a client actually thinks in — a chest logo, a back print — rather
  # than a bare number of centimetres. Read from settings, never hard-coded.
  #
  # `config_for` hands back deeply symbolised keys, so the lookup is `:key`. A
  # string subscript returns nil, and the translation key then loses its last
  # segment and resolves to the whole parent hash rather than raising.
  def print_size_presets
    Rails.application.config.tshirt.generation[:print_size_presets].map do |preset|
      preset.merge(label: t("client.designs.new.size_presets.#{preset.fetch(:key)}"))
    end
  end

  # What a raster print file is, in the terms that decide whether it will look
  # right: its size on the garment, its definition, and the width beyond which
  # the model's own resolution stops keeping up.
  def design_file_facts(design)
    stats = design.stats

    {
      t("designs.facts.size") => print_size(stats),
      t("designs.facts.definition") => ("#{stats['width_px']} px" if stats["width_px"]),
      t("designs.facts.resolution") => ("#{stats['dpi']} dpi" if stats["dpi"]),
      t("designs.facts.sharp_up_to") => ("#{stats['net_width_cm']} cm" if stats["net_width_cm"])
    }.compact
  end

  private
    def print_size(stats)
      width = stats["print_width_cm"]
      height = stats["print_height_cm"]
      "#{width.to_i} × #{height.to_i} cm" if width && height
    end
end
