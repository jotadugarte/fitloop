# frozen_string_literal: true

# Prefer bin/rails fitloop:purge_all for full workspace reset.

namespace :sheet_stocks do
  desc "Remove orphan sheet stocks not shown in UI (e.g. 1000x2000 ghosts). Use PROJECT_ID=87 to scope."
  task prune_orphans: :environment do
    scope = Project.all
    scope = scope.where(id: ENV["PROJECT_ID"]) if ENV["PROJECT_ID"].present?

    scope.find_each do |project|
      stocks = project.sheet_stocks.order(:sort_order, :id)
      next if stocks.size <= 1

      puts "Project #{project.id} (#{project.title.truncate(40)}):"
      stocks.each do |stock|
        puts "  - id=#{stock.id} #{stock.width_mm}x#{stock.height_mm} qty=#{stock.quantity.inspect} sort=#{stock.sort_order}"
      end

      if ENV["DESTROY"] == "1"
        keep_id = ENV["KEEP_ID"]&.to_i
        to_destroy = keep_id ? stocks.where.not(id: keep_id) : stocks.offset(1)
        count = to_destroy.count
        to_destroy.destroy_all
        SheetStocks::InvalidateNestingOutputs.call(project.reload)
        puts "  destroyed #{count} row(s); nesting outputs cleared."
      else
        puts "  (dry run) set DESTROY=1 to delete extras; optional KEEP_ID=<id> to keep one row."
      end
    end
  end
end
