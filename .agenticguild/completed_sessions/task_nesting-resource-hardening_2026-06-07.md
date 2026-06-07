# Nesting Resource Hardening

## Overview
This session covers hardening the nesting execution pipeline by making the execution process robust against timeouts (avoiding orphan/zombie Python subprocesses), ensuring immediate workspace file cleanup from `tmp/nesting_runs/`, and configuring concurrent workers in Solid Queue appropriately for the deployment hardware environment.

---

## Architectural Decisions & Edge Cases

### 1. Robust Timeout OS Process Kill
- **Context**: Ruby's `Timeout.timeout` raises an asynchronous `Timeout::Error` inside the thread running `Nesting::CliRunner.call`. However, `Open3.popen3` does not kill the spawned OS subprocess when an exception breaks the block. The Python subprocess remains running and consumes CPU/RAM.
- **Proposed Solution**:
  - In `Nesting::CliRunner.call`, we must wrap the process execution block in a `begin ... ensure` structure or handle the interruption to guarantee that if the block is aborted (due to `Timeout::Error` or standard cancellations), the spawned process is forcefully terminated using `Process.kill("KILL", pid)` or `Process.kill("TERM", pid)` followed by a wait to ensure the child process is reaped.
  - Since `Timeout.timeout` raises the error asynchronously, we should register the pid of the active command execution so that an outer rescue/ensure block can access it and clean it up.
  - Note: `CliRunner#run_cli!` already has a `Process.kill("TERM", pid)` inside `wait_with_progress_poll` if `@cancel_check&.call` is true. But if `Timeout::Error` is raised, it breaks out of `Open3.popen3` immediately.
  - **Orphan Verification**: Rails is the originator of the child process. If Rails exits the execution loop (due to a timeout or cancellation) but the process with the stored `pid` is still alive in the OS (verified via `Process.kill(0, pid)` which does not raise `Errno::ESRCH`), that process is *by definition* orphan (running in the background without any Rails runner waiting for or using its output). It is safe and necessary to terminate it.
  - **Complex Files & Deadlines**: The database default value for `projects.nesting_time_limit_sec` is **600 seconds (10 minutes)**. Rails sets the `Timeout.timeout` dynamically based on this project attribute (`NestingTimeLimitSec.from_project`).
    * If a file is complex and the execution takes time, Python's nesting engine internally monitors this limit and stops optimization gracefully *before* the timeout, writing a `partial` layout output and exiting status 0.
    * The Ruby-side timeout acts strictly as a **security fail-safe**: it only triggers if the Python subprocess hangs (e.g., gets stuck in a C++ native loop or fails to respond). In this extreme case, killing the process is necessary to release resources, and the run is marked as `failed` (or `partial` if some output was already written).

### 2. Immediate `/tmp` Cleanup
- **Context**: Every nesting run materializes DXF attachments to disk under `tmp/nesting_runs/:id/`. Currently, these files are never cleaned up, creating a potential disk-space exhaustion issue over time.
- **Proposed Solution**:
  - We will modify `Nesting::JobRunner` or `Nesting::CliRunner` to ensure that `FileUtils.rm_rf(work_dir)` is called at the end of the execution (both on success and failure/timeout/cancel).
  - *Edge Case*: We must not clean it up *before* active storage attachments are processed. Attachments are uploaded in `attach_outputs!` (inside `CliRunner#call`) or `attach_outputs_if_present!` (inside `JobRunner#handle_timeout!`).
  - Therefore, cleanup must occur at the very end of `JobRunner.call` inside an `ensure` block, after all database operations and Active Storage uploads have completed.

### 3. Solid Queue Concurrency Limit
- **Context**: We need to create/update `config/solid_queue.yml` to set concurrent worker limits.
- **Hardware & Capacity Analysis**:
  - **Machine Specs**: Dell G3 3579 Gaming (Intel i7-8750H: 6 physical cores / 12 logical threads, burst >4.0 GHz, 16 GiB of RAM, 477 GiB SSD).
  - **Nesting Job Profile**: Each Python nesting execution is CPU-intensive and runs at **~100% CPU on 1 core**. Memory usage is lightweight (~100MB to 500MB).
  - **Queue Concurrency Strategy**: With 6 physical cores and 16 GiB of RAM, running **3 concurrent workers** in the `nesting` queue is perfectly viable and highly optimal.
    * Up to 3 users can perform complex nesting operations simultaneously, using 3 physical cores at 100%.
    * The remaining **3 physical cores (and 6 logical threads)** are more than enough to handle Puma (Rails HTTP server), Action Cable (WebSockets), and PostgreSQL with absolutely zero UI lag or latency.
    * For traffic spikes (e.g. 5 concurrent nesting requests), 3 will process in parallel immediately, and the remaining 2 will wait in Solid Queue (showing "En cola..." in the UI) and start as soon as active runs finish.

---

## Risk Matrix
- **Risk 1: Double Process Kill / Race Condition** - Attempting to kill a PID that has already finished.
  - *Mitigation*: Catch `Errno::ESRCH` (No such process) when executing `Process.kill`.
- **Risk 2: Clean up before Upload** - Active Storage upload failing because files were deleted too early.
  - *Mitigation*: Ensure cleanup is in the outermost `ensure` block of `JobRunner#call` once the database transactions and uploads have completely finished.

---

## Domain Model
*(No new domain models/VOs are introduced. This is pure system orchestration and configuration hardening)*

---

<implementation_plan>
  <phase name="Phase 1: Test Baseline &amp; Coverage">
    <step id="1" status="complete">
      <instruction>Run the existing RSpec tests to establish a green baseline and check coverage.</instruction>
      <command>bundle exec rspec spec/services/nesting/job_runner_spec.rb spec/services/nesting/cli_runner_spec.rb</command>
    </step>
  </phase>

  <phase name="Phase 2: Timeout OS Process Kill (TDD)">
    <step id="2" status="complete">
      <instruction>Write a test in `spec/services/nesting/cli_runner_spec.rb` to assert that if execution is interrupted (e.g. raises Timeout::Error), any active PID spawned by Open3 is killed using Process.kill("TERM", pid) followed by Process.kill("KILL", pid) fallback.</instruction>
    </step>
    <step id="3" status="complete">
      <instruction>Modify `Nesting::CliRunner` to track the child process pid and introduce a begin/ensure block in `run_cli!` or `call` to verify if the process is still alive and kill it robustly on interruption, rescuing Errno::ESRCH.</instruction>
    </step>
    <step id="4" status="complete">
      <instruction>Verify that the tests for Timeout OS process kill pass.</instruction>
      <command>bundle exec rspec spec/services/nesting/cli_runner_spec.rb</command>
    </step>
  </phase>

  <phase name="Phase 3: Immediate /tmp Workspace Cleanup (TDD)">
    <step id="5" status="complete">
      <instruction>Write a test in `spec/services/nesting/job_runner_spec.rb` to assert that after the NestingJob finishes (on success, partial, or failure/timeout), the workspace directory `tmp/nesting_runs/:id/` is completely removed from disk.</instruction>
    </step>
    <step id="6" status="complete">
      <instruction>Modify `Nesting::JobRunner#call` with an ensure block that removes the workspace directory using `FileUtils.rm_rf(work_dir)` once Active Storage attachments have been uploaded.</instruction>
    </step>
    <step id="7" status="complete">
      <instruction>Verify that the cleanup tests pass.</instruction>
      <command>bundle exec rspec spec/services/nesting/job_runner_spec.rb</command>
    </step>
  </phase>

  <phase name="Phase 4: Solid Queue Concurrency Limit Configuration">
    <step id="8" status="complete">
      <instruction>Update `config/queue.yml` to partition queue workers: limit the `nesting` queue to exactly 3 concurrent workers (threads: 1, processes: 3) and keep `default,analytics` queues on standard workers.</instruction>
    </step>
    <step id="9" status="complete">
      <instruction>Run the entire test suite to ensure no regressions were introduced and coverage remains 100%.</instruction>
      <command>bundle exec rspec</command>
    </step>
  </phase>
</implementation_plan>

