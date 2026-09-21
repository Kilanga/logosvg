module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      # Deuxième lecture de session de l'application, à côté de celle du
      # concern Authentication — et elle se déréférence pareil. Le
      # développement tourne avec `strict_loading_by_default` : sans le
      # préchargement, `session.user` lève ici à chaque ouverture de socket,
      # donc sur chaque page, toutes les dix secondes pendant que Turbo
      # retente. Le symptôme n'est pas une erreur à l'écran : c'est une page
      # qui ne se met jamais à jour.
      def set_current_user
        if session = Session.includes(:user).find_by(id: cookies.signed[:session_id])
          self.current_user = session.user
        end
      end
  end
end
