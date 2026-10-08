# Decided on 01/10/2026 and confirmed on 08/10/2026: two levels, not three —
# the Retouche at 49 € TTC and the custom job on quote. The seeds already said
# so, but seeds never run in production: the « Contrôle » level at 19 € was
# still offered on pretatirer.fr. Deactivated, not deleted: reviews already
# sold under it keep their reference.
class RetireControlReviewLevel < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE review_levels SET active = FALSE, updated_at = NOW() WHERE key = 'check'"
    execute "UPDATE review_levels SET price_cents = 4900, updated_at = NOW() WHERE key = 'retouch'"
  end

  def down
    execute "UPDATE review_levels SET active = TRUE, updated_at = NOW() WHERE key = 'check'"
  end
end
