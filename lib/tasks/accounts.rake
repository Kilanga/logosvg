namespace :data do
  desc "Compte toutes les données liées à des comptes ; CONFIRM=1 les supprime (voir PurgeAccounts)"
  task purge_accounts: :environment do
    PurgeAccounts.call(confirm: ENV["CONFIRM"] == "1")
  end
end

namespace :admin do
  # The only way an administrator account comes to exist: sign-up refuses the
  # role, and the seeds never run in production. The password is typed, never
  # passed as an argument — it would sit in the shell history and in `ps`.
  #
  #   docker exec -it <conteneur web> bin/rails admin:create EMAIL=vous@exemple.fr
  desc "Crée un compte administrateur (EMAIL=…, mot de passe demandé)"
  task create: :environment do
    require "io/console"

    email = ENV["EMAIL"].presence || (print("Adresse : ") || $stdin.gets.to_s.strip)
    abort "Adresse manquante." if email.blank?
    abort "Un compte existe déjà avec #{email}." if User.exists?(email_address: email.strip.downcase)

    password = $stdin.getpass("Mot de passe (#{User::MINIMUM_PASSWORD_LENGTH} caractères minimum) : ")
    abort "Les deux saisies diffèrent." unless password == $stdin.getpass("Encore une fois : ")

    first_name = ENV.fetch("FIRST_NAME", "Admin")
    last_name = ENV.fetch("LAST_NAME", "Prêt-à-tirer")
    user = User.new(email_address: email, password: password, first_name: first_name, last_name: last_name,
                    role: "admin", terms_accepted_at: Time.current)

    if user.save
      puts "Administrateur créé : #{user.email_address}"
    else
      abort user.errors.full_messages.to_sentence
    end
  end
end
