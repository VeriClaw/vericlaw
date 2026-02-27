#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/generate_competitive_v2_final_report.sh [--regression-report PATH] [--scorecard-report PATH] [--direct-report PATH] [--output PATH]

Builds the final competitive V2 comparative report artifact from regression, scorecard,
and direct-harness reports.
EOF
}

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
regression_report_path="${project_root}/tests/competitive_regression_gate_report.json"
scorecard_report_path="${project_root}/tests/competitive_scorecard_report.json"
direct_report_path="${project_root}/tests/competitive_direct_benchmark_report.json"
output_path="${project_root}/tests/competitive_v2_final_competitive_report.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --regression-report)
      [[ $# -ge 2 ]] || { echo "Missing value for --regression-report" >&2; exit 2; }
      regression_report_path="$2"
      shift 2
      ;;
    --scorecard-report)
      [[ $# -ge 2 ]] || { echo "Missing value for --scorecard-report" >&2; exit 2; }
      scorecard_report_path="$2"
      shift 2
      ;;
    --direct-report)
      [[ $# -ge 2 ]] || { echo "Missing value for --direct-report" >&2; exit 2; }
      direct_report_path="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "Missing value for --output" >&2; exit 2; }
      output_path="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$(dirname "${output_path}")"

python3 - "${project_root}" "${regression_report_path}" "${scorecard_report_path}" "${direct_report_path}" "${output_path}" <<'PY'
import datetime as dt
import json
import pathlib
import sys

project_root = pathlib.Path(sys.argv[1]).resolve()
regression_path = pathlib.Path(sys.argv[2])
scorecard_path = pathlib.Path(sys.argv[3])
direct_path = pathlib.Path(sys.argv[4])
output_path = pathlib.Path(sys.argv[5])


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def resolve(path: pathlib.Path) -> pathlib.Path:
    if path.is_absolute():
        return path
    return (project_root / path).resolve()


def to_rel(path: pathlib.Path) -> str:
    try:
        return path.resolve().relative_to(project_root).as_posix()
    except Exception:
        return path.as_posix()


errors = []


def load_required_json(path_value: pathlib.Path, label: str):
    path = resolve(path_value)
    if not path.is_file():
        errors.append(f"missing {label} report: {to_rel(path)}")
        return {}, path
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle), path
    except Exception as exc:  # noqa: BLE001
        errors.append(f"invalid {label} report JSON: {to_rel(path)} ({exc})")
        return {}, path


regression, regression_path = load_required_json(regression_path, "regression")
scorecard, scorecard_path = load_required_json(scorecard_path, "scorecard")
direct, direct_path = load_required_json(direct_path, "direct harness")

pass_fail_projects = [project for project in regression.get("pass_fail_projects", []) if isinstance(project, str) and project]
if not pass_fail_projects:
    pass_fail_projects = [project for project in scorecard.get("pass_fail_projects", []) if isinstance(project, str) and project]

scorecard_only_projects = [
    project for project in scorecard.get("scorecard_only_projects", []) if isinstance(project, str) and project
]
comparative_dimensions = scorecard.get("comparative_dimensions", {})
if not isinstance(comparative_dimensions, dict):
    comparative_dimensions = {}

vericlaw_payload = scorecard.get("vericlaw", {})
if not isinstance(vericlaw_payload, dict):
    vericlaw_payload = {}
vericlaw_feature = vericlaw_payload.get("feature_parity", {})
if not isinstance(vericlaw_feature, dict):
    vericlaw_feature = {}
vericlaw_deployment = vericlaw_payload.get("deployment_maturity", {})
if not isinstance(vericlaw_deployment, dict):
    vericlaw_deployment = {}
vericlaw_security = vericlaw_payload.get("security_non_regression", {})
if not isinstance(vericlaw_security, dict):
    vericlaw_security = {}

direct_projects = direct.get("projects", {})
if not isinstance(direct_projects, dict):
    direct_projects = {}

feature_status = "pass"
deployment_status = "pass"
security_status = "pass"
performance_status = "pass" if regression.get("status") == "pass" else "fail"

if performance_status != "pass":
    errors.append("competitive regression gate status is not pass")

if not vericlaw_feature:
    feature_status = "fail"
    errors.append("missing vericlaw feature parity snapshot")
if not vericlaw_deployment:
    deployment_status = "fail"
    errors.append("missing vericlaw deployment maturity snapshot")
if not vericlaw_security:
    security_status = "fail"
    errors.append("missing vericlaw security non-regression snapshot")

feature_peer_deltas = {}
deployment_peer_comparison = {}
for project in pass_fail_projects:
    project_dimensions = comparative_dimensions.get(project, {})
    if not isinstance(project_dimensions, dict):
        project_dimensions = {}

    feature_map = project_dimensions.get("feature_parity", {})
    if not isinstance(feature_map, dict):
        feature_map = {}
        feature_status = "fail"
        errors.append(f"missing feature parity comparison for {project}")
    else:
        for counter_id, counter_data in feature_map.items():
            if not isinstance(counter_data, dict):
                continue
            delta = counter_data.get("delta_vericlaw_minus_project")
            if is_number(delta) and delta < 0:
                feature_status = "fail"
                errors.append(f"feature parity below {project}: {counter_id}")
    feature_peer_deltas[project] = feature_map

    deployment_map = project_dimensions.get("deployment_maturity", {})
    if not isinstance(deployment_map, dict):
        deployment_map = {}
        deployment_status = "fail"
        errors.append(f"missing deployment maturity comparison for {project}")
    deployment_peer_comparison[project] = deployment_map

security_peer_alignment = {}
strict_peer_mismatches = 0
for project in pass_fail_projects:
    peer_payload = direct_projects.get(project, {})
    if not isinstance(peer_payload, dict):
        peer_payload = {}
    peer_security = peer_payload.get("security_non_regression", {})
    if not isinstance(peer_security, dict):
        peer_security = {}

    mismatches = {}
    if not peer_security:
        mismatches["__missing_security_snapshot__"] = {"vericlaw": vericlaw_security, project: None}
    else:
        for key, expected_value in vericlaw_security.items():
            observed_value = peer_security.get(key)
            if observed_value != expected_value:
                mismatches[key] = {"vericlaw": expected_value, project: observed_value}

    if mismatches:
        strict_peer_mismatches += len(mismatches)
        security_status = "fail"
    security_peer_alignment[project] = {
        "matches_vericlaw_security_defaults": len(mismatches) == 0,
        "mismatches": mismatches,
    }

metric_outcomes = []
for check in regression.get("checks", []):
    if not isinstance(check, dict):
        continue
    metric_id = check.get("metric_id")
    direction = check.get("direction")
    vericlaw_value = check.get("vericlaw_value")
    comparisons = {}
    for comparison in check.get("comparisons", []):
        if not isinstance(comparison, dict):
            continue
        project = comparison.get("project")
        if not isinstance(project, str) or not project:
            continue
        peer_value = comparison.get("competitor_value")
        ratio = comparison.get("vericlaw_to_competitor_ratio")
        assessment = None
        if is_number(vericlaw_value) and is_number(peer_value):
            if direction == "higher_is_better":
                assessment = "vericlaw_better" if vericlaw_value >= peer_value else "vericlaw_worse"
            else:
                assessment = "vericlaw_better" if vericlaw_value <= peer_value else "vericlaw_worse"
        comparisons[project] = {
            "value": peer_value,
            "vericlaw_to_peer_ratio": ratio,
            "assessment": assessment,
        }
    metric_outcomes.append(
        {
            "metric_id": metric_id,
            "metric_label": metric_id,
            "direction": direction,
            "vericlaw_value": vericlaw_value,
            "regression_gate_status": check.get("status"),
            "strict_peer_comparisons": comparisons,
        }
    )

openclaw_dimensions = comparative_dimensions.get("openclaw", {})
openclaw_report = None
openclaw_feature_trailing = []
openclaw_security_trailing = []
if isinstance(openclaw_dimensions, dict):
    openclaw_feature = openclaw_dimensions.get("feature_parity", {})
    if not isinstance(openclaw_feature, dict):
        openclaw_feature = {}
    for counter_id, counter_data in openclaw_feature.items():
        if isinstance(counter_data, dict) and is_number(counter_data.get("delta_vericlaw_minus_project")):
            if counter_data.get("delta_vericlaw_minus_project", 0) < 0:
                openclaw_feature_trailing.append(counter_id)

    openclaw_security = {}
    openclaw_payload = direct_projects.get("openclaw", {})
    if isinstance(openclaw_payload, dict):
        openclaw_security = openclaw_payload.get("security_non_regression", {})
    if not isinstance(openclaw_security, dict):
        openclaw_security = {}
    security_delta = {}
    for key, expected_value in vericlaw_security.items():
        observed_value = openclaw_security.get(key)
        if observed_value != expected_value:
            security_delta[key] = {"vericlaw": expected_value, "openclaw": observed_value}
            openclaw_security_trailing.append(key)

    openclaw_report = {
        "project": "openclaw",
        "scope": "scorecard_only_non_gating",
        "note": "OpenClaw is excluded from strict quantitative pass/fail gating and included for scorecard insights only.",
        "feature_delta_vs_vericlaw": openclaw_feature,
        "deployment_delta_vs_vericlaw": openclaw_dimensions.get("deployment_maturity", {}),
        "security_delta_vs_vericlaw": security_delta,
    }

overall_status = "pass"
for component_status in (performance_status, feature_status, deployment_status, security_status):
    if component_status != "pass":
        overall_status = "fail"
        break
if errors:
    overall_status = "fail"

report = {
    "schema_version": "competitive-v2-final-comparative-report",
    "generated_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "baseline_id": regression.get("baseline_id") or scorecard.get("baseline_id"),
    "scenario": direct.get("scenario"),
    "source_artifacts": {
        "regression": to_rel(regression_path),
        "scorecard": to_rel(scorecard_path),
        "direct_harness": to_rel(direct_path),
        "openclaw_scorecard": "config/competitive_scorecards/openclaw_v2_scorecard.json",
    },
    "strict_quantitative_peers": {
        "scope": "pass_fail_quantitative",
        "projects": pass_fail_projects,
        "performance": {
            "gate_status": performance_status,
            "source": regression.get("status"),
            "regression_metrics": regression.get("regression_metrics", []),
            "metric_outcomes": metric_outcomes,
        },
        "feature": {
            "vericlaw_feature_parity": vericlaw_feature,
            "peer_deltas": feature_peer_deltas,
        },
        "deployment": {
            "vericlaw_deployment_maturity": vericlaw_deployment,
            "peer_comparison": deployment_peer_comparison,
        },
        "security": {
            "vericlaw_security_defaults": vericlaw_security,
            "peer_alignment": security_peer_alignment,
        },
    },
    "outcome_summary": {
        "overall_status": overall_status,
        "performance": {
            "status": performance_status,
            "source": to_rel(regression_path),
        },
        "feature": {
            "status": feature_status,
            "vericlaw_feature_parity": vericlaw_feature,
        },
        "deployment": {
            "status": deployment_status,
            "vericlaw_deployment_maturity": vericlaw_deployment,
        },
        "security": {
            "status": security_status,
            "strict_peer_mismatches": strict_peer_mismatches,
        },
        "openclaw_scorecard_insights": {
            "feature_counters_where_vericlaw_trails": sorted(set(openclaw_feature_trailing)),
            "security_controls_where_openclaw_trails": sorted(set(openclaw_security_trailing)),
        },
    },
    "scorecard_only_projects": scorecard_only_projects,
}

if openclaw_report is not None:
    report["openclaw_scorecard_only"] = openclaw_report
if errors:
    report["errors"] = errors

output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
if overall_status != "pass":
    raise SystemExit(1)
PY

report_display="${output_path}"
if [[ "${output_path}" == "${project_root}/"* ]]; then
  report_display="${output_path#${project_root}/}"
fi
echo "competitive-v2-final-report: report=${report_display}"
