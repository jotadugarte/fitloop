# Nesting thorough optimizer — checkpoint

**Checkpoint SHA:** `c95aa56200357bfabd481beb22dfd9ca202fc6d6` (`c95aa56`)

Revert the nesting engine to this commit to discard optimizer phases 0–7 and start again.

```bash
git reset --hard c95aa56
```

Do not delete this file when rebasing the optimizer work; it marks the baseline.
