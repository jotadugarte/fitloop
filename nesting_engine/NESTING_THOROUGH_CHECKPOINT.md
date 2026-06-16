# Nesting thorough optimizer — checkpoint

Revert the nesting engine to the commit that adds this file to restart the
thorough-optimizer implementation from a clean baseline.

```bash
git log --oneline -- nesting_engine/NESTING_THOROUGH_CHECKPOINT.md
# use the first commit that introduces this file (checkpoint marker)

git reset --hard <checkpoint-commit-sha>
```

Do not delete this file when rebasing the optimizer work; it marks the baseline.
