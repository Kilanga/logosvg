# Be sure to restart your server when you modify this file.

# Strict content security policy. Only the third parties the application
# actually needs are allowed: Cloudflare Turnstile for the anti-robot widget,
# Stripe for payments, and OpenStreetMap for the directory map tiles.
# See docs/SPEC.md, "Sécurité, RGPD et anti-abus".
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri    :self
    policy.object_src  :none
    policy.frame_ancestors :none

    # Typefaces are self-hosted, so no font CDN is allowed.
    policy.font_src :self

    policy.img_src :self,
                   :data,
                   "https://*.tile.openstreetmap.org"

    policy.script_src :self,
                      "https://challenges.cloudflare.com",
                      "https://js.stripe.com"

    policy.style_src :self

    # Ink swatches carry a colour that only exists at runtime, as part of a
    # generated palette, so it is written as a style attribute. Allowing inline
    # style *attributes* cannot execute script, and <style> elements stay
    # restricted to :self by the directive above.
    policy.style_src_attr :unsafe_inline

    policy.connect_src :self

    # Turnstile widget and Stripe Checkout / Elements frames.
    policy.frame_src "https://challenges.cloudflare.com",
                     "https://js.stripe.com",
                     "https://hooks.stripe.com"

    policy.form_action :self

    policy.upgrade_insecure_requests unless Rails.env.local?
  end

  # Enforced, not merely reported: a violation should break a page in
  # development rather than reach production unnoticed.
  config.content_security_policy_report_only = false
end
