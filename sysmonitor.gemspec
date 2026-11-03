# frozen_string_literal: true

require_relative "lib/sysmonitor/version"

Gem::Specification.new do |spec|
  spec.name = "sysmonitor"
  spec.version = Sysmonitor::VERSION
  spec.authors = ["Oleg Sokolov"]
  spec.summary = "System & process memory info from /proc (Ruby port of the sysinfo.cr surface)"
  spec.description = "Sysmonitor reads RAM (total/available), process snapshots with RSS, " \
                     "per-process-tree memory and per-core CPU load. Linux via /proc, " \
                     "macOS memory via sysctl/vm_stat. Built as the system-info backend " \
                     "for Taskforge's memory-aware worker pool."
  spec.homepage = "https://github.com/OrelSokolov/sysmonitor"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.13"
end
