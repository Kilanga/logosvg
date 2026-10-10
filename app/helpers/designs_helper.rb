module DesignsHelper
  # 1, 2 or 3: where a proposal stands among those of its click. Counted, not
  # stored: a broadcast renders one card alone and still has to say which.
  def proposal_number(design)
    return 1 if design.batch_token.blank?

    Design.where(batch_token: design.batch_token).where(id: ..design.id).count
  end

  # The technique under the name the shop in context gives it, falling back to
  # the catalogue's. A client who arrived by a workshop's link should read that
  # workshop's words.
  def workshop_technique_label(entry)
    context_printer&.technique_for(entry.key)&.display_label || entry.label
  end

  def technique_family_hint(entry)
    t("designs.family_hint.#{entry.family}")
  end

  # A handful of common fabric colours to preview against — not the colour of
  # any particular order, which is only chosen later, at the print request.
  # See docs/SPEC.md, "Aperçu" → "aperçu sur t-shirt avec couleurs de tissu".
  GARMENT_SWATCHES = {
    white: "#FFFFFF", black: "#1A1A1A", heather: "#9CA3AF", navy: "#1E2A4A", red: "#B3261E"
  }.freeze

  def garment_swatches = GARMENT_SWATCHES

  # Who finished a reviewed design. A plucked name rather than a walk through
  # the associations: this partial is rendered by broadcasts and lists that
  # preload nothing of the kind.
  def reviewing_designer_name(design)
    return nil if design.source_review_id.nil?

    Review.where(id: design.source_review_id).joins(:designer_profile)
          .pick("designer_profiles.display_name")
  end

  # The silhouette's body spans 52 % of its width, and a medium t-shirt is
  # about 52 cm across: one centimetre of print is one percent of the drawing.
  # Bounded so a tiny logo stays visible and a full back never overflows.
  GARMENT_SHARE_RANGE = (8..46)

  def garment_print_share(design)
    width = design.print_width_cm.presence ||
            Rails.application.config.tshirt.generation[:default_print_width_cm]
    width.to_i.clamp(GARMENT_SHARE_RANGE)
  end

  def design_status_pill(design)
    style = case design.status
    when "ready"  then "pill-success"
    when "failed" then "pill-warning"
    else "border border-line text-muted"
    end

    tag.span t("enums.design.status.#{design.status}"), class: "pill #{style}"
  end

  # The subject of a pending action, whatever kind of record it hangs off.
  # Written here so the dashboard view does not have to know.
  def dashboard_action_subject(action)
    case action.record
    when Design then action.record.prompt.truncate(60)
    when PrintRequest then action.record.printer.name
    when Review then action.record.design.prompt.truncate(60)
    end
  end

  # Where acting on it happens. Here rather than in ClientDashboard: a service
  # that builds URLs cannot be called without a request in hand.
  def dashboard_action_path(action)
    case action.kind
    when :design_failed then new_design_path
    when :design_unsent then new_design_print_request_path(action.record)
    when :print_request_silent then print_request_path(action.record)
    when :review_delivered, :review_proposal then review_path(action.record)
    end
  end

  # The one hint that carries its own deadline rather than a fixed sentence.
  def dashboard_action_hint(action)
    if action.kind == :review_proposal
      t("client.dashboards.show.action.review_proposal.hint",
        date: l(action.record.proposal_expires_at, format: :long))
    else
      t("client.dashboards.show.action.#{action.kind}.hint")
    end
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

  # What happened to a client's own picture on its way to the workshop's
  # format, said plainly, beside the picture and its result. The technique is
  # what decides: a screen, a thread or a flex take it into a few flat inks, a
  # digital print keeps it whole. Read from what the service recorded, never
  # guessed.
  def print_changes(design)
    stats = design.stats || {}
    changes = design.vector? ? vector_changes(design, stats) : raster_changes(stats)
    changes << t(design.remove_background? ? "designs.changes.background_removed" : "designs.changes.background_kept")
    changes
  end

  # Whether trying the picture with another technique means anything: not at a
  # shop that prints only one way. Counted rather than loaded — the panel is
  # also rendered from a broadcast, where nothing is preloaded.
  def other_techniques_offered?(design)
    design.printer_id.nil? || PrinterTechnique.where(printer_id: design.printer_id).count > 1
  end

  private
    def vector_changes(design, stats)
      [
        t("designs.changes.flattened", count: design.inks_count.to_i),
        t("designs.changes.traced"),
        t("designs.changes.width", width: (stats["print_width_cm"] || design.print_width_cm).to_i)
      ]
    end

    def raster_changes(stats)
      changes = [ t("designs.changes.kept_whole") ]
      if stats["print_width_cm"] && stats["print_height_cm"]
        changes << t("designs.changes.raster_size", width: stats["print_width_cm"].to_i,
                                                    height: stats["print_height_cm"].to_i, dpi: stats["dpi"])
      end
      if stats["upscale"].to_f > 1.05
        changes << t("designs.changes.enlarged", factor: number_with_precision(stats["upscale"], precision: 1,
                                                                               strip_insignificant_zeros: true))
      end
      changes
    end

    def print_size(stats)
      width = stats["print_width_cm"]
      height = stats["print_height_cm"]
      "#{width.to_i} × #{height.to_i} cm" if width && height
    end
end
