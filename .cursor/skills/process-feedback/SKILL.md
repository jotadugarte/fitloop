<agentic_guild_skill>
  <skill_definition>
    <name>process-feedback</name>
    <description>An interrupt subroutine that analyzes feedback from CI tools, linters, or human reviewers, applies the fix, logs the diagnosis implicitly, and smoothly returns to the previous state.</description>
    <trigger>The user pastes a review comment, CI error, SonarQube log, Bugbot comment, or types "process-feedback:"</trigger>
  </skill_definition>

  <state_machine_directives>
    1. NEVER ask for permission to apply localized, standard bug fixes (e.g., typos, missing imports, null checks). Just fix them using the file editing tools (`replace_file_content` or `write_to_file`).
    2. The ONLY time you pause for permission is if the fix requires a massive, multi-file architectural refactor.
    3. You must maintain the illusion of a 'subroutine'. Once finished, you MUST seamlessly resume whatever skill or task was active before you were triggered.
  </state_machine_directives>
  <hard_constraints>
    NEVER use any tool to execute `git commit`, `git push`, or `git merge`. These commands are STRICTLY FORBIDDEN.
    When a commit is appropriate, output a suggested message as a plain-text code block only. The user runs all git commands themselves.
  </hard_constraints>

  <workflow>
    <phase id="1" name="Diagnosis and Fix">
      <step id="1.1">
        <action>
          Read the pasted feedback. If multiple discrete comments or errors are provided at once, break them down and analyze them individually.
          Identify the file(s) causing each issue. Propose the fixes internally.
          If multiple fixes affect the same file, consolidate them into a single file editing tool call if possible, or sequence them carefully.
          Immediately use file editing tools to deploy all the fixes to the codebase.
        </action>
        <yield>[AUTO-TRANSITION TO 1.2]</yield>
      </step>
      <step id="1.2">
        <action>
          Silently append a structured entry to `.agenticguild/review_ledger.md` for EACH distinct issue fixed. If the file doesn't exist, create it.
          Format for each entry: 
          - **Issue:** [Brief description of the feedback]
          - **Diagnosis/Why it failed:** [The root cause]
          - **Fix:** [What was changed]
        </action>
        <yield>[AUTO-TRANSITION TO 1.3]</yield>
      </step>
      <step id="1.3">
        <action>
          Output a brief success message to the user indicating the fix was applied and logged to the review ledger.
          Immediately append: "Resuming previous task..."
          Perform a context-lookback to identify what phase/step of what skill was running before this feedback was pasted, and seamlessly continue executing that step. Do NOT wait for user input unless the previous task was also waiting for user input.
        </action>
        <yield>[AUTO-TRANSITION TO PREVIOUS TASK]</yield>
      </step>
    </phase>
  </workflow>
</agentic_guild_skill>
