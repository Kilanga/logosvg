# Demonstration data. Idempotent: run it as often as you like.
#
#   bin/rails db:seed
#
# The point of these three shops is the technique filter. One does screen
# printing only, one DTF only, and one does both families — and delivers its
# sublimation as an SVG in CMYK, because that is what its workflow expects.
# Filtering by technique must show a different list each time.

PASSWORD = "motdepasse-demo".freeze

def account!(email, **attributes)
  User.find_or_create_by!(email_address: email) do |user|
    user.password = PASSWORD
    user.terms_accepted_at = Time.current
    user.assign_attributes(attributes)
  end
end

def workshop!(user, name:, techniques:, **attributes)
  printer = Printer.find_or_initialize_by(user: user)
  printer.assign_attributes(name: name, orders_email: user.email_address, **attributes)
  printer.save!

  techniques.each do |row|
    printer.techniques.find_or_initialize_by(technique: row.fetch(:technique))
           .tap { |t| t.assign_attributes(row) }.save!
  end

  printer.update!(status: :published)
  # Depuis l'étape 6, publier ne suffit plus : une fiche sans abonnement actif
  # n'apparaît nulle part.
  subscription = Subscription.find_or_initialize_by(printer: printer)
  subscription.update!(plan: attributes[:featured] ? "atelier_plus" : "listing",
                       status: "active", current_period_end: 1.month.from_now)
  printer
end

def review_level!(key, **attributes)
  ReviewLevel.find_or_initialize_by(key: key).tap { |l| l.assign_attributes(attributes) }.save!
end

def designer!(user, display_name:, levels:, **attributes)
  profile = DesignerProfile.find_or_initialize_by(user: user)
  profile.assign_attributes(display_name: display_name, **attributes)
  profile.save!
  profile.review_levels = ReviewLevel.where(key: levels)
  profile
end

ActiveRecord::Base.transaction do
  # --- Sérigraphie seule -----------------------------------------------------
  workshop!(
    account!("thabor@example.invalid", first_name: "Claire", last_name: "Martin",
                                       role: "printer", city: "Rennes"),
    name: "Sérigraphie du Thabor",
    description: "Atelier de sérigraphie artisanale, six couleurs maximum, textile bio certifié GOTS.",
    address: "12 rue de Paris", postal_code: "35000", city: "Rennes",
    latitude: 48.1173, longitude: -1.6778,
    pickup: true, provides_textile: true, textile_label: :gots,
    standard_lead_days: 10, min_order_qty: 20, response_time_hours: 24,
    placements: %w[ chest_center back_full ],
    max_print_width_cm: 30, max_print_height_cm: 40,
    techniques: [
      { technique: "screen_printing", max_colors: 4, output_format: "svg",
        color_space: "rgb", primary: true,
        note: "Quatre écrans au plus par commande." }
    ]
  )

  # --- DTF seul --------------------------------------------------------------
  workshop!(
    account!("presse-rhone@example.invalid", first_name: "Nora", last_name: "Belkacem",
                                             role: "printer", city: "Lyon"),
    name: "Presse Rhône",
    description: "Transfert numérique grand format, dégradés et photo. Expédition partout en France.",
    address: "3 quai Perrache", postal_code: "69002", city: "Lyon",
    latitude: 45.7640, longitude: 4.8357,
    ships: true, shipping_zones: %w[ france europe ], shipping_lead: 5,
    standard_lead_days: 7, accepts_client_textile: true, featured: true,
    placements: %w[ chest_center chest_left back_full ],
    max_print_width_cm: 40, max_print_height_cm: 50,
    techniques: [
      { technique: "dtf", label: "Impression photo toutes couleurs",
        output_format: "png", color_space: "rgb", primary: true }
    ]
  )

  # --- Les deux familles, avec des attentes de fichier bien à lui ------------
  workshop!(
    account!("atelier-loire@example.invalid", first_name: "Hugo", last_name: "Salaun",
                                              role: "printer", city: "Nantes"),
    name: "Atelier Loire",
    description: "Broderie, flocage et sublimation. Petites séries et pièces uniques.",
    address: "8 rue Kervégan", postal_code: "44000", city: "Nantes",
    latitude: 47.2184, longitude: -1.5536,
    express_available: true, express_lead_hours: 48, pickup: true,
    standard_lead_days: 12,
    placements: %w[ chest_left sleeve tote_bag ],
    max_print_width_cm: 25, max_print_height_cm: 35,
    techniques: [
      { technique: "embroidery", label: "Broderie fil à fil", max_colors: 6,
        output_format: "svg", color_space: "rgb", primary: true,
        max_print_width_cm: 20, max_print_height_cm: 20 },
      { technique: "flex", label: "Flocage 2 couleurs", max_colors: 2,
        output_format: "svg", color_space: "rgb", primary: false },
      # Le catalogue dit PNG ; cet atelier veut un SVG en CMJN. C'est exactement
      # ce que le modèle doit permettre.
      { technique: "sublimation", label: "Sublimation polyester",
        output_format: "svg", color_space: "cmyk", primary: false,
        note: "Polyester clair uniquement." }
    ]
  )

  # --- Niveaux de vérification ------------------------------------------------
  # ⚠ DÉCISION OUVERTE : les prix restent à fixer. Ceux-ci ne servent qu'à la
  # démonstration.
  review_level!("check", name: "Contrôle", price_cents: 1900, turnaround_hours: 24,
                         revisions_included: 1, position: 1,
                         description: "Un graphiste vérifie le fichier : tracés, encres, netteté des bords.")
  review_level!("retouch", name: "Retouche", price_cents: 4900, turnaround_hours: 48,
                           revisions_included: 2, position: 2,
                           description: "Reprise du visuel pour l'impression : nettoyage, séparation des encres, ajustements.")
  review_level!("custom", name: "Création sur mesure", price_cents: nil, turnaround_hours: 96,
                          revisions_included: 3, position: 3,
                          description: "Redessin complet à partir de votre idée. Le prix est proposé par le graphiste.")

  # --- Graphistes -------------------------------------------------------------
  # L'un peut travailler, l'autre non : c'est la règle de l'étape 7 rendue
  # visible dès les données de démonstration.
  designer!(
    account!("ines@example.invalid", first_name: "Inès", last_name: "Nadeau",
                                     role: "designer", city: "Lyon"),
    display_name: "Inès Nadeau",
    bio: "Dix ans de sérigraphie et d'illustration vectorielle. Je reprends vos visuels pour qu'ils sortent proprement des écrans.",
    city: "Lyon", latitude: 45.7640, longitude: 4.8357,
    specialties: %w[ illustration vectorisation retouche ], languages: %w[ fr en ],
    status: "active", payouts_enabled: true, accepting_work: true,
    rating_avg: 4.8, ratings_count: 23,
    levels: %w[ check retouch custom ]
  )

  designer!(
    account!("tom@example.invalid", first_name: "Tom", last_name: "Vidal",
                                    role: "designer", city: "Bordeaux"),
    display_name: "Tom Vidal",
    bio: "Lettering et logos, surtout pour le textile. Je travaille en aplats et j'aime les contraintes d'encres.",
    city: "Bordeaux", latitude: 44.8378, longitude: -0.5792,
    specialties: %w[ lettering logo ], languages: %w[ fr ],
    status: "pending_review", payouts_enabled: false,
    levels: %w[ check ]
  )

  account!("admin@example.invalid", first_name: "Sam", last_name: "Oubre", role: "admin")
  account!("client@example.invalid", first_name: "Camille", last_name: "Rousseau", role: "client")
end

puts "#{Printer.listed.count} ateliers publiés, #{PrinterTechnique.count} techniques déclarées."
puts "#{DesignerProfile.listed.count} graphiste(s) publié(s) sur #{DesignerProfile.count}, " \
     "#{ReviewLevel.offered.count} niveaux de vérification."
puts "Comptes de démonstration, mot de passe #{PASSWORD} :"
User.order(:role, :email_address).pluck(:role, :email_address).each do |role, email|
  puts "  #{role.ljust(8)} #{email}"
end
