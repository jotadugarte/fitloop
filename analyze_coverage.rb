require 'json'

resultset_path = File.expand_path('coverage/.resultset.json', __dir__)
unless File.exist?(resultset_path)
  puts "No resultset found at #{resultset_path}"
  exit 1
end

data = JSON.parse(File.read(resultset_path))
key = data.keys.first
coverage_data = data[key]['coverage']

uncovered_files = []

coverage_data.each do |filepath, filecov|
  # Skip non-app files or external files if any
  next unless filepath.include?('/app/')
  
  lines = filecov['lines'] || []
  branches = filecov['branches'] || {}
  
  executable_lines = []
  uncovered_lines = []
  
  lines.each_with_index do |cov, idx|
    line_num = idx + 1
    next if cov.nil? # Nil means not executable
    
    executable_lines << line_num
    uncovered_lines << line_num if cov == 0
  end
  
  uncovered_branches = []
  branches.each do |branch_name, branch_cov|
    branch_cov.each do |cond, count|
      uncovered_branches << "#{branch_name} -> #{cond}" if count == 0
    end
  end
  
  if uncovered_lines.any? || uncovered_branches.any?
    total_exec = executable_lines.size
    pct = total_exec > 0 ? ((total_exec - uncovered_lines.size).to_f / total_exec * 100).round(2) : 100.0
    
    uncovered_files << {
      path: filepath.sub(File.expand_path(__dir__) + '/', ''),
      percentage: pct,
      uncovered_lines: uncovered_lines,
      uncovered_branches: uncovered_branches
    }
  end
end

uncovered_files.sort_by! { |f| f[:percentage] }

uncovered_files.each do |f|
  puts "--------------------------------------------------"
  puts "File: #{f[:path]} (#{f[:percentage]}% coverage)"
  if f[:uncovered_lines].any?
    puts "  Uncovered Lines: #{f[:uncovered_lines].join(', ')}"
  end
  if f[:uncovered_branches].any?
    puts "  Uncovered Branches/Paths:"
    f[:uncovered_branches].each do |b|
      puts "    - #{b}"
    end
  end
end
