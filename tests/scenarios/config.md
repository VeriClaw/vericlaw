## Scenario: Config validate with missing file
- When I run `vericlaw config validate --config /nonexistent/path.json`
- Then the output contains "error"
- And the exit code is 1

## Scenario: Config validate reports success
- When I run `vericlaw config validate --config config/example.json`
- Then the output contains "valid"
- And the exit code is 0
