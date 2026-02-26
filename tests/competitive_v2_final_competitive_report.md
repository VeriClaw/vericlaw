# Competitive V2 Final Comparative Report

- Generated: 2026-02-26T15:22:24Z
- Baseline: anywhere-v2-freeze-competitive-baselines
- Strict quantitative peers: zeroclaw, nullclaw
- Scorecard-only reference: openclaw
- Overall status: **PASS**

## 1) Strict quantitative peers (pass/fail): ZeroClaw + NullClaw

| Metric | Direction | Quasar | ZeroClaw | NullClaw | Quasar/ZeroClaw | Quasar/NullClaw | Regression gate |
|---|---|---:|---:|---:|---:|---:|---|
| Startup (ms) | lower_is_better | 1.59 | 10 | 8 | 0.159 | 0.199 | pass |
| Idle RSS (MB) | lower_is_better | 3.473 | 4.1 | 1 | 0.847 | 3.473 | pass |
| Dispatch latency p95 (ms) | lower_is_better | 1.216 | 13.4 | 14 | 0.091 | 0.087 | pass |
| Throughput (ops/sec) | higher_is_better | 921.331 | 80 | 78 | 11.517 | 11.812 | pass |
| Binary size (MB) | lower_is_better | 0.168 | 8.8 | 0.662 | 0.019 | 0.254 | n/a |
| Container size (MB) | lower_is_better | 31.615 | 42 | 48 | 0.753 | 0.659 | n/a |

### Security outcome (strict peers only)

- zeroclaw: **aligned** (mismatches: none)
- nullclaw: **aligned** (mismatches: none)

### Feature + deployment outcome (strict peers only)

- zeroclaw: feature deltas (providers=0, channels=0, tools=1); deployment smoke matrix quasar=6, zeroclaw=5.
- nullclaw: feature deltas (providers=0, channels=0, tools=2); deployment smoke matrix quasar=6, nullclaw=4.

## 2) OpenClaw (scorecard-only, non-gating)

- OpenClaw is included for scorecard insight only and is not part of strict quantitative pass/fail gates.
- Feature deltas vs Quasar:
  - providers: quasar=3, openclaw=4, delta=-1
  - channels: quasar=3, openclaw=4, delta=-1
  - tools: quasar=12, openclaw=14, delta=-2
- Deployment deltas vs Quasar:
  - multi_arch_image: quasar=True, openclaw=True
  - signed_artifacts: quasar=True, openclaw=True
  - smoke_matrix: quasar=6, openclaw=6
- Security gaps vs Quasar defaults: empty_allowlist_denies_all, encrypt_secrets_at_rest

## 3) Outcome summary

- Performance: **pass**
- Security: **pass**
- Feature: **pass**
- Deployment: **pass**
- Overall: **pass**
