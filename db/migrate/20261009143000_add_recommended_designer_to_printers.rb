# Decided on 09/10/2026: a workshop may recommend one designer to its clients,
# shown first, as « Recommandé par votre atelier », when they ask for a review.
class AddRecommendedDesignerToPrinters < ActiveRecord::Migration[8.1]
  def change
    add_reference :printers, :recommended_designer_profile,
                  foreign_key: { to_table: :designer_profiles, on_delete: :nullify }
  end
end
