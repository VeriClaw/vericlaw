## Scenario: Unknown command
- When I run `vericlaw nonexistent-command`
- Then the exit code is 1

## Scenario: Unknown flag
- When I run `vericlaw --nonexistent-flag`
- Then the exit code is 1
