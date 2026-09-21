module Workshop
  class BaseController < SpaceController
    layout "workshop"

    private
      def space_key = :workshop_space

      # The signed-in professional's own workshop, fetched by its own query
      # rather than walked to from `Current.user`.
      #
      # Development runs with `strict_loading_by_default`, so reaching an
      # association from a record nobody preloaded raises — and the current user
      # is reached on every request, by Pundit, before any controller runs.
      # Preloading `:printer` alongside the session would make every client page
      # pay for a record only workshops own, and would teach the authentication
      # code about roles. Loading it here, once per request and only in this
      # space, costs the same single query and stays where the need is.
      # `subscription` et `techniques` viennent avec : ce sont les deux faces de
      # l'atelier que cet espace montre — l'abonnement en tableau de bord et sur
      # l'écran de facturation, les techniques sur la fiche. Les charger ici,
      # c'est deux petites requêtes sur des pages qui ne les affichent pas
      # toutes ; les charger contrôleur par contrôleur, c'est rouvrir la même
      # panne au prochain écran ajouté.
      def current_printer
        return @current_printer if defined?(@current_printer)

        @current_printer = Printer.includes(:subscription, :techniques)
                                  .find_by(user_id: Current.user.id)
      end
      helper_method :current_printer
  end
end
