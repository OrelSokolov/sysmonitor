# frozen_string_literal: true

# sysmonitor — Ruby-порт поверхности sysinfo.cr (github.com/OrelSokolov/sysinfo.cr),
# нужной пулу тяжёлых задач Taskforge. Синхронный, как и оригинал:
# вызывающий сам решает, когда обновлять снапшоты.
#
#   Sysmonitor.memory                 — RAM total/available (KB); nil = неизвестно
#   Sysmonitor.refresh_processes      — пересобрать снапшот pid/ppid/RSS
#   Sysmonitor.processes              — последний снапшот
#   Sysmonitor.process_tree_memory_kb — RSS процесса + всех потомков (KB)
#   Sysmonitor.refresh_cpu            — сэмплировать тики, обновить загрузку ядер
#   Sysmonitor.cpu_percentages        — busy % по ядрам с прошлого сэмпла
#   Sysmonitor.core_count             — число ядер (nil без CPU-бэкенда)
#
# Платформы (как в sysinfo.cr):
#   Linux — /proc (meminfo, per-pid status, stat). Верхний уровень /proc
#           содержит только thread-group leaders, так что RSS нитей не
#           задваивается.
#   macOS — sysctl hw.memsize + vm_stat (только память); снапшот
#           процессов пуст, CPU-бэкенда нет.
#   Прочие — memory возвращает nil, процессы пусты.

require_relative "sysmonitor/version"

module Sysmonitor
  # Общая RAM; размеры в KB.
  class Memory
    attr_reader :total_kb, :available_kb

    def initialize(total_kb, available_kb)
      @total_kb = total_kb
      @available_kb = available_kb
    end

    def used_kb
      [total_kb - available_kb, 0].max
    end

    # Процент занятого; 0 при неизвестном total.
    def percent
      return 0 if total_kb <= 0

      ((used_kb.to_f / total_kb) * 100.0).round.clamp(0, 100)
    end
  end

  # Одна запись процесса (не нить) из снапшота. Отдельное имя, чтобы не
  # теневать ::Process в вызывающем коде.
  ProcessEntry = Struct.new(:pid, :parent_pid, :memory_kb)

  OS = case RUBY_PLATFORM
       when /linux/ then :linux
       when /darwin/ then :darwin
       else :other
       end
  private_constant :OS

  @processes = [].freeze
  @by_pid = {}.freeze
  @children = {}.freeze
  @cpu_percentages = [].freeze
  @last_cpu_ticks = nil
  @mutex = Mutex.new

  class << self
    # Общая RAM; nil = неизвестно на этой платформе.
    def memory
      case OS
      when :linux then linux_memory
      when :darwin then darwin_memory
      end
    end

    # Пересобрать снапшот процессов (вызывать вне горячего пути UI —
    # чтение нескольких сотен записей занимает миллисекунды).
    def refresh_processes
      case OS
      when :linux then linux_refresh_processes
      else store_processes([])
      end
    end

    # Последний снапшот (пуст до первого refresh_processes).
    def processes
      @mutex.synchronize { @processes }
    end

    # Резидентная память процесса и всех его потомков в KB — ближайшее
    # к «сколько реально ест эта задача», поскольку шеллы плодят детей
    # (компиляторы, rake, cc). 0 без снапшота/при неизвестном корне.
    # Защищено от циклов.
    def process_tree_memory_kb(root_pid)
      return 0 unless root_pid

      by_pid, children = @mutex.synchronize { [@by_pid, @children] }
      total = 0
      visited = {}
      queue = [root_pid]
      while (pid = queue.shift)
        next if visited[pid]

        visited[pid] = true
        total += by_pid[pid].memory_kb if by_pid[pid]
        queue.concat(children[pid] || [])
      end
      total
    end

    # Сэмплировать счётчики CPU и обновить проценты по ядрам. Первый
    # вызов только запоминает базовую линию: до второго вызова проценты
    # читаются как нули (вызовы стоит разносить ~на 1 с).
    def refresh_cpu
      cores = linux_cpu_ticks
      @cpu_percentages =
        if cores && (previous = @last_cpu_ticks) && previous.size == cores.size
          cores.zip(previous).map do |current, before|
            busy = current[0] - before[0]
            idle = current[1] - before[1]
            total = busy + idle
            total.zero? ? 0 : ((busy.to_f / total) * 100.0).round.clamp(0, 100)
          end
        elsif cores
          Array.new(cores.size, 0)
        else
          []
        end
      @last_cpu_ticks = cores
    end

    # Busy % по ядрам с прошлого refresh_cpu (пусто до refresh_cpu;
    # нули после единственного вызова).
    def cpu_percentages
      @mutex.synchronize { @cpu_percentages }
    end

    # Число ядер — размер per-core массива (nil на платформах без
    # CPU-бэкенда).
    def core_count
      refresh_cpu
      size = cpu_percentages.size
      size.positive? ? size : nil
    end

    private

    # Запомнить свежий снапшот и пересобрать индексы (дерево потомков).
    def store_processes(processes)
      by_pid = {}
      children = {}
      processes.each do |entry|
        by_pid[entry.pid] = entry
        (children[entry.parent_pid] ||= []) << entry.pid if entry.parent_pid
      end
      @mutex.synchronize do
        @processes = processes.freeze
        @by_pid = by_pid.freeze
        @children = children.freeze
      end
    end

    def linux_memory
      total_kb = nil
      available_kb = nil
      File.foreach("/proc/meminfo") do |line|
        kb = line.split[1]&.to_i
        total_kb = kb if line.start_with?("MemTotal:")
        available_kb = kb if line.start_with?("MemAvailable:")
        break if total_kb && available_kb
      end
      return nil unless total_kb && available_kb

      Memory.new(total_kb, available_kb)
    rescue Errno::ENOENT
      nil
    end

    def darwin_memory
      total = `sysctl -n hw.memsize`.to_i
      return nil if total.zero?

      stats = `vm_stat`
      page_kb = stats[/page size of (\d+) bytes/, 1].to_i / 1024
      pages = stats[/Pages free:\s+(\d+)/, 1].to_i + stats[/Pages inactive:\s+(\d+)/, 1].to_i
      Memory.new(total / 1024, pages * page_kb)
    end

    def linux_refresh_processes
      entries = []
      Dir.glob("/proc/[0-9]*").each do |proc_dir|
        pid = File.basename(proc_dir).to_i
        next if pid.zero?

        ppid = nil
        rss_kb = 0
        begin
          File.foreach(File.join(proc_dir, "status")) do |line|
            if line.start_with?("PPid:")
              ppid = line[5..].strip.to_i
            elsif line.start_with?("VmRSS:")
              rss_kb = line[7..].split.first.to_i
              break
            end
          end
        rescue Errno::ENOENT, Errno::ESRCH
          # TOCTOU: процесс исчез между glob и чтением status — его нет.
          next
        end
        # PPid 0 = init / нить ядра (у нитей ядра нет VmRSS, они и так 0).
        entries << ProcessEntry.new(pid, ppid&.positive? ? ppid : nil, rss_kb)
      end
      store_processes(entries)
    end

    # Per-core (busy, idle) тики из /proc/stat
    # ("cpuN: user nice system idle iowait irq softirq steal ...").
    def linux_cpu_ticks
      return nil unless OS == :linux

      cores = []
      File.foreach("/proc/stat") do |line|
        break unless line.start_with?("cpu")
        next if line.start_with?("cpu ") # агрегатная строка идёт первой

        fields = line.split
        busy = [1, 2, 3, 6, 7, 8].sum { |i| fields[i].to_i }
        idle = fields[4].to_i + fields[5].to_i
        cores << [busy, idle]
      end
      cores.empty? ? nil : cores
    rescue Errno::ENOENT
      nil
    end
  end
end
