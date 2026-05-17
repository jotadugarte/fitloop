# CbC Generation Prompt Template

**Purpose:** A reusable XML constraint wrapper to inject into code generation steps. This template enforces Correct-by-Construction principles at the moment of generation — not just at audit time.

**Usage:** The `start-task` skill reads this file during Step 3.2 (implementation) and uses it to frame the generation request. Skills or prompts that generate domain logic should wrap their request in this structure.

---

## The Template

When generating implementation code for a step, frame the prompt using this XML structure:

```xml
<context>
  <!-- Paste the relevant spec excerpt from docs/core/SPEC.md and the
       current task_[name].md step being implemented. -->
</context>

<role>
  You are an expert software engineer practicing Correct-by-Construction.
  Your code must satisfy the step's requirements on the first attempt.
  You follow the project's deterministic coding standards without exception.
</role>

<constraints>
  1. ALL loops must have a fixed, hard-coded upper bound. No unbounded iteration.
  2. NO function may exceed 60 lines of code.
  3. You MUST include at least one Pre-condition assertion and one Post-condition
     assertion per critical function (data mutations, service calls, state changes).
  4. NEVER use primitive types (String, Integer, raw object) for domain concepts.
     Use Value Objects (Ruby) or Branded Types (TypeScript) to make invalid
     states unrepresentable (e.g., `EmailAddress`, `ValidAge`, `UserId`).
  5. Maximum cyclomatic complexity of 10 per method. No deeply nested logic.
  6. Every new public method must be traceable to a REQ-ID from docs/core/SPEC.md.
</constraints>

<reflection>
  Before outputting the final code, critique your own proposed implementation
  against the constraints above. Check for:
  - Any function exceeding 60 lines
  - Any loop without a hard upper bound
  - Any missing Pre-condition or Post-condition assertion
  - Any domain concept represented as a raw primitive type
  - Any method with cyclomatic complexity > 10 (deeply nested conditionals, long chains of if/else)
  - Any method without a REQ-ID reference

  If you detect a violation, fix the code first. Only then output the final result.
</reflection>

<output_format>
  CONDITIONAL VISIBILITY: The reflection output is shown only when violations were found and corrected.
  - If violations were detected and fixed: Output the <reflection> block first (listing what was wrong and how it was corrected), then the corrected code block.
  - If no violations were found: Suppress the reflection entirely. Output only the implementation code block. Do not mention that the self-audit ran.
  Do not re-explain the constraints in either case.
</output_format>
```

---

## Integration Notes

- This template is **not a standalone skill**. It is a generation constraint wrapper referenced by `start-task` Step 3.2.
- The `<context>` block should be filled by the AI with the specific step details from the active session file before generating.
- The `<reflection>` block forces the AI to self-audit before output. This is the highest-leverage quality gate in the CbC pattern.
- For **non-domain utility code** (helpers, formatters, pure functions with no domain semantics), constraints 4 and 6 may be relaxed at the AI's discretion — but this must be noted in the reflection.
