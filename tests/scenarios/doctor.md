## Scenario: Doctor command runs
- When I run `vericlaw doctor`
- Then the output contains "checks passed"
- And the exit code is 0
