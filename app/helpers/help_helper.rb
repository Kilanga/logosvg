# The help pages: a guide and questions for workshops, a sheet a workshop hands
# to its clients, questions for clients, and a guide for designers (decided on
# 09/10/2026).
#
# The text lives in config/locales/fr.yml. The figures in it do not: they are
# read from config/settings.yml here, so a quota or a price changed there is
# right on these pages the same day, without anyone rereading them.
module HelpHelper
  def help_values
    @help_values ||= begin
      settings = Rails.application.config.tshirt
      subscriptions = settings.subscriptions
      {
        platform: settings.platform_name,
        quota_per_day: settings.generation.fetch(:quota_per_day),
        proposals: settings.generation.fetch(:proposals_per_request),
        max_refinements: settings.generation.fetch(:max_refinements),
        attachment_days: settings.clients.fetch(:attachment_days),
        listing_generations: subscriptions.fetch(:monthly_generations).fetch(:listing),
        listing_price: help_price(subscriptions.fetch(:price_listing_cents)),
        atelier_plus_price: help_price(subscriptions.fetch(:price_atelier_plus_cents)),
        trial_days: subscriptions.fetch(:trial_period_days),
        grace_days: subscriptions.fetch(:past_due_grace_days),
        reminder_hours: settings.print_requests.fetch(:reminder_after_hours),
        expire_days: settings.print_requests.fetch(:expire_after_days),
        auto_accept_days: settings.reviews.fetch(:auto_accept_days),
        fee_percent: (settings.reviews.fetch(:platform_fee_rate) * 100).round,
        claim_hours: settings.reviews.fetch(:designer_claim_timeout_hours),
        unclaimed_hours: settings.reviews.fetch(:unclaimed_refund_hours),
        proposal_hours: settings.reviews.fetch(:proposal_expiry_hours),
        reminder_days: settings.reviews.fetch(:acceptance_reminder_days).join(" puis "),
        dispute_alert_count: settings.reviews.fetch(:dispute_alert_count),
        dispute_alert_days: settings.reviews.fetch(:dispute_alert_days),
        support_email: settings.support_email
      }
    end
  end

  # A translated string with the figures put in. Arrays of questions come back
  # from I18n uninterpolated, so every string goes through here.
  def help_text(string) = I18n.interpolate(string.to_s, help_values)

  def help_price(cents) = number_to_currency(cents / 100.0, unit: "€", format: "%n %u", precision: 0)
end
