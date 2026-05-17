# Testing Strategy Matrix

**Purpose:** Defines the testing requirements and coverage rules. No feature may be merged without fulfilling these testing contracts.

## 1. Traceability Requirement
* **The [REQ-ID] Rule:** EVERY test block (e.g., `it(...)` or `test(...)`) must include the specific `[REQ-ID]` from `SPEC.md` that it is verifying. Untraced tests are considered invalid.

## 2. The Testing Pyramid
| Layer | Framework | Rule of Engagement | Target Coverage |
|---|---|---|---|
| **Domain / Services** | [e.g., RSpec / Jest] | 100% logic coverage. Mock all external I/O. | 100% |
| **Controllers / APIs** | [e.g., RSpec Requests] | Test HTTP routing, status codes, and auth payload. | 90% |
| **UI / Components** | [e.g., Vitest / RNTL] | Test accessibility (a11y) and user interactions. | 85% |
| **E2E / System** | [e.g., Playwright / Maestro] | Test complete critical user flows. | Key Flows Only |

## 3. Mocking & Stubbing Rules
* **External APIs:** MUST be mocked. Tests must never make live network calls.
* **Time/Dates:** MUST be frozen (e.g., `travel_to` or `jest.useFakeTimers()`) to prevent intermittent failures.
* **Randomness:** Seeds MUST be hardcoded during test runs to ensure deterministic output.
