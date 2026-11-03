# frozen_string_literal: true

require "sysmonitor"

LINUX = RUBY_PLATFORM.include?("linux")

RSpec.describe Sysmonitor do
  describe ".memory" do
    it "reads total/available RAM and computes percent" do
      mem = described_class.memory
      skip "no memory backend on this platform" if mem.nil?

      expect(mem.total_kb).to be_positive
      expect(mem.available_kb).to be_positive
      expect(mem.available_kb).to be <= mem.total_kb
      expect(mem.percent).to be_between(0, 100)
    end
  end

  describe ".refresh_processes / .process_tree_memory_kb" do
    it "snapshots processes and sums the RSS of the own tree" do
      skip "no process backend on this platform" unless LINUX

      described_class.refresh_processes
      expect(described_class.processes.size).to be_positive

      own = described_class.process_tree_memory_kb(Process.pid)
      expect(own).to be_positive

      unknown = described_class.process_tree_memory_kb(nil)
      expect(unknown).to eq(0)
    end
  end

  describe ".core_count" do
    it "counts CPU cores" do
      skip "no CPU backend on this platform" unless LINUX

      expect(described_class.core_count).to be_positive
    end
  end
end
