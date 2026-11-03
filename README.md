# sysmonitor

Системная информация для Ruby: память, снапшоты процессов с RSS,
память дерева процессов, загрузка ядер. Ruby-порт поверхности
[sysinfo.cr](https://github.com/OrelSokolov/sysinfo.cr). Бэкенд
системной информации для [taskforge](https://github.com/OrelSokolov/taskforge) —
пула тяжёлых задач, ограниченного по памяти.

## API

```ruby
require "sysmonitor"

Sysmonitor.memory
# => #<Sysmonitor::Memory total_kb=..., available_kb=...>
Sysmonitor.memory.available_kb / 1024  # MB свободно

Sysmonitor.refresh_processes            # снапшот pid/ppid/RSS
Sysmonitor.processes.size
Sysmonitor.process_tree_memory_kb(pid)  # RSS процесса + всех потомков, KB

Sysmonitor.refresh_cpu                  # сэмпл тиков (проценты — со второго вызова)
Sysmonitor.cpu_percentages              # busy % по ядрам
Sysmonitor.core_count                   # число ядер
```

Библиотека синхронная, как оригинальный Rust-crate `sysinfo`: вызывающий
сам решает, когда и что обновлять. Потокобезопасна.

## Платформы

- **Linux** — всё через `/proc` (meminfo, per-pid status, stat). Верхний
  уровень `/proc` содержит только thread-group leaders, так что RSS нитей
  не задваивается.
- **macOS** — только память (`sysctl hw.memsize` + `vm_stat`); снапшот
  процессов пуст, CPU-бэкенда нет.
- **прочие** — `memory` → `nil`, процессы пусты.

## Установка

В Gemfile:

```ruby
gem "sysmonitor"
```

## Разработка

```
bundle install
bundle exec rspec
```

MIT License.
