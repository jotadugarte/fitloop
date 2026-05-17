# frozen_string_literal: true

module Dxf
  # Resolves the Python interpreter for nesting_engine CLI scripts.
  module Python
    def self.executable
      venv_python = Rails.root.join(".venv/bin/python")
      return venv_python.to_s if File.executable?(venv_python)

      "python3"
    end
  end
end
