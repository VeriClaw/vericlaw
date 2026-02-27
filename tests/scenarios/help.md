## Scenario: Display help
- When I run `vericlaw --help`
- Then the output contains "Usage:"
- And the output contains "Commands:"
- And the exit code is 0

## Scenario: Display help with -h shorthand
- When I run `vericlaw -h`
- Then the output contains "Usage:"
- And the exit code is 0
