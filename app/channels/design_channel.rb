# Pushes a design's state to the page watching it.
#
# Broadcast from jobs, which is why development runs Solid Cable rather than
# the async adapter: the worker is a different process from the web server, and
# an in-process adapter would never reach the browser.
class DesignChannel
  def self.stream_name(design) = "design:#{design.token}"

  # Replaces the whole design panel rather than patching pieces of it: the
  # panel looks entirely different between generating, ready and failed, and a
  # single replace is easier to reason about than three partial updates.
  # Le design est relu avec son fichier : le partiel l'affiche, et celui que
  # l'appelant tient vient le plus souvent d'un travail de fond, donc d'un
  # `Design.find` nu. Sans cette relecture, la diffusion lève en développement —
  # et elle lève au pire moment, juste après qu'un design a échoué, si bien que
  # l'écran du client ne recevrait jamais la nouvelle.
  def self.broadcast(design)
    Turbo::StreamsChannel.broadcast_replace_to(
      stream_name(design),
      target: "design_#{design.token}",
      partial: "client/designs/design",
      locals: { design: Design.with_attached_print_file.find(design.id) }
    )
  end
end
