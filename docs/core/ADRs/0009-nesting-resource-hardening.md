# ADR-0009: Nesting Resource Hardening

**Status:** Accepted  
**Date:** 2026-06-07

## Context and problem statement

The sheet nesting execution pipeline had several vulnerabilities related to resource management and scalability:
1. When nesting runs timed out (e.g., via `Timeout.timeout`), the spawned Python child process was orphaned and left running in the OS, consuming 100% CPU on one core.
2. materializing DXF input and output files under `tmp/nesting_runs/:id/` left lingering workspace files on disk indefinitely, risking disk exhaustion.
3. Queue worker concurrency was unoptimized for the server hardware specifications (Dell G3 VM: 6 physical cores, 16 GiB RAM).

## Decision drivers

- Eliminate CPU resource leaks caused by orphaned Python subprocesses.
- Prevent local disk space exhaustion by ensuring prompt workspace file cleanup.
- Optimize Solid Queue worker concurrency to balance active nesting throughput and web server/database responsiveness.

## Considered options

1. **Option A** – Keep simple process signaling and rely on periodic background cron cleanup scripts for `/tmp`.
2. **Option B (Chosen)** – Implement direct, robust process termination with fallback signals inside Rails, wrap job execution in a strict `ensure` cleanup block, and isolate the `nesting` queue with a 3-process concurrency boundary.

## Decision outcome

**Chosen option:** Option B.

### Rationale
- **Timeout OS Process Kill**: Added PID tracking and process escalation in `Nesting::CliRunner#run_cli!`. If the thread is interrupted, an `ensure` block sends `TERM` to the child process, polls its status up to 3 times (with `sleep 0.1` intervals), and sends `KILL` if it remains active. A post-condition assertion ensures the subprocess is dead.
- **Immediate Workspace Cleanup**: Wrapped `Nesting::JobRunner#call` in a top-level `ensure` block that calls `FileUtils.rm_rf(work_dir)` once Active Storage uploads are completed, guaranteeing folder removal on both success and failure states.
- **Solid Queue Concurrency**: Partitioned queues in `config/queue.yml`. The `default,analytics` queues run with 3 threads, while the CPU-heavy `nesting` queue runs in 3 single-threaded processes. This isolates CPU-intensive tasks and leaves 3 physical cores free for web and database services.

### Positive consequences

- Guaranteed cleanup of timed-out, cancelled, or aborted Python processes.
- Zero disk leaks from nesting runs.
- Structured queue limits prevent CPU starvation of critical Rails/Postgres services during traffic spikes.

### Negative consequences

- Mocking process signals in tests requires more defensive `Process.kill` stubs to prevent actual system signal leaks during RSpec runs.
