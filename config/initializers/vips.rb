# libvips refuses its "untrusted" loaders as soon as image_processing is
# required, and the SVG loader is one of them — a document format that can pull
# in remote resources and expand entities.
#
# Except that a screen-printing design *is* an SVG, and the only rendering a
# client ever sees is a raster of it. Left blocked, every vector design would
# come back without a preview — and silently, since the file itself is stored
# fine. So the SVG loader is unblocked, on its own, and everything else libvips
# distrusts stays refused.
#
# What makes that defensible is that no SVG reaches the renderer unexamined:
# SvgInspector refuses scripts, event handlers, entities, external references
# and remote stylesheets, and DesignPreview runs it again on the stored bytes
# immediately before rasterising. See app/services/svg_inspector.rb.
Rails.application.config.after_initialize do
  Vips.block("VipsForeignLoadSvg", false) if defined?(Vips) && Vips.respond_to?(:block)
end
