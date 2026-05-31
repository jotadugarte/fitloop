# frozen_string_literal: true

module SplitSpecHelpers
  module_function

  def write_mother_dxf(path, rings)
    python = Rails.root.join("nesting_engine/.venv/bin/python")
    script = <<~PY
      import ezdxf
      doc = ezdxf.new("R2010")
      doc.modelspace().add_lwpolyline(
          #{rings.first.map { |point| [ point[0], point[1] ] }.inspect},
          close=True,
          dxfattribs={"layer": "PIECES"},
      )
      doc.saveas(#{path.to_s.inspect})
    PY
    system(python.to_s, "-c", script, exception: true)
  end
end

RSpec.configure do |config|
  config.include SplitSpecHelpers
end
