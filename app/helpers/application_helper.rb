module ApplicationHelper
  # The platform name is still an open decision, so it is read from
  # config/settings.yml rather than written into templates or locale strings.
  def platform_name
    Rails.application.config.tshirt.platform_name
  end

  # "Section — Platform" on inner pages, the tagline on the home page.
  def page_title
    section = content_for(:title)
    section.present? ? "#{section} — #{platform_name}" : "#{platform_name} — #{t('platform.tagline')}"
  end

  # Registration mark, the crosshair a printer aligns each screen against.
  # Decorative by default: it carries no meaning a screen reader needs.
  def registration_mark(css_class: nil)
    tag.span class: [ "registration-mark", css_class ], aria: { hidden: true }
  end
end
