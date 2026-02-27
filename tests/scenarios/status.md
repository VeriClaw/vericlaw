## Scenario: Status command runs
- When I run `vericlaw status`
- Then the output contains "version"
- And the exit code is 0

## Scenario: Status with --json flag
- When I run `vericlaw status --json`
- Then the output contains "version"
- And the exit code is 0
