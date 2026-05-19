# frozen_string_literal: true

namespace :fitloop do
  desc "Destroy all projects, sheet stocks, nesting runs, temp dirs, and orphan storage blobs"
  task purge_all: :environment do
    counts = Workspace.purge_all!
    puts "Purged #{counts[:projects]} project(s), #{counts[:nesting_dirs]} nesting run dir(s), #{counts[:blobs]} orphan blob(s)."
  end

  desc "Destroy all ephemeral projects and nesting temp dirs (keeps saved/legacy rows if any)"
  task purge_ephemeral: :environment do
    count = Workspace.purge_all_ephemeral!
    puts "Purged #{count} ephemeral project(s) and nesting temp dirs."
  end
end
