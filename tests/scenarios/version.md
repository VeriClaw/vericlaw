## Scenario: Display version
- When I run `vericlaw --version`
- Then the output contains "vericlaw"
- And the exit code is 0

## Scenario: Version includes build info
- When I run `vericlaw --version`
- Then the output matches "vericlaw [0-9]+\.[0-9]+\.[0-9]+"
