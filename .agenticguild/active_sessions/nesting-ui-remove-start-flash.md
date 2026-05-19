# Nesting UI: remove green flash on job start

- Goal: Stop showing flash notice (“Trabajo de anidado iniciado”) on project page; nesting progress UI is enough.
- Controllers: `NestingRunsController#create`, `ProjectLayersController#update` — redirect without `notice:` on success.
