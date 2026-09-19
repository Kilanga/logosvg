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
  def self.broadcast(design)
    Turbo::StreamsChannel.broadcast_replace_to(
      stream_name(design),
      target: "design_#{design.token}",
      partial: "client/designs/design",
      locals: { design: design }
    )
  end
end
