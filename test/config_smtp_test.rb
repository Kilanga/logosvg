require "test_helper"

# Le relais d'envoi se règle par l'environnement (17/10/2026 : passage de
# Brevo à la boîte OVH, port 465). Un secret vide de GitHub arrive comme une
# chaîne vide : il doit compter comme absent, pas comme un port 0.
class ConfigSmtpTest < ActiveSupport::TestCase
  test "production reads the relay from the environment, with the right encryption for each port" do
    source = Rails.root.join("config/environments/production.rb").read

    assert_includes source, 'ENV["SMTP_ADDRESS"].presence || "smtp-relay.brevo.com"'
    assert_includes source, "tls: smtp_port == 465"
    assert_includes source, "enable_starttls_auto: smtp_port != 465"
    %w[ SMTP_ADDRESS SMTP_PORT ].each do |name|
      assert_includes Rails.root.join("config/deploy.yml").read, "- #{name}"
      assert_includes Rails.root.join(".kamal/secrets").read, "#{name}=$#{name}"
    end
  end
end
