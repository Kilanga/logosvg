module Printer
  class BaseController < SpaceController
    layout "printer"

    private
      def space_key = :printer_space
  end
end
