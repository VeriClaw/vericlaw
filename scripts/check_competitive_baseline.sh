#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/check_competitive_baseline.sh [--report PATH] [--baseline PATH] [--direct-report PATH] [--scorecard-report PATH] [--regression-report PATH]

Validates Quasar benchmark output against local SLO thresholds from
config/anywhere_v2_competitive_baseline.toml.
Writes comparative feature/deployment scorecard dimensions to
tests/competitive_scorecard_report.json by default and a regression gate
artifact at tests/competitive_regression_gate_report.json.
EOF
}

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report_path="${project_root}/tests/competitive_benchmark_report.json"
baseline_path="${project_root}/config/anywhere_v2_competitive_baseline.toml"
direct_report_path="${project_root}/tests/competitive_direct_benchmark_report.json"
scorecard_report_path="${project_root}/tests/competitive_scorecard_report.json"
regression_report_path="${project_root}/tests/competitive_regression_gate_report.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      [[ $# -ge 2 ]] || { echo "Missing value for --report" >&2; exit 2; }
      report_path="$2"
      shift 2
      ;;
    --baseline)
      [[ $# -ge 2 ]] || { echo "Missing value for --baseline" >&2; exit 2; }
      baseline_path="$2"
      shift 2
      ;;
    --direct-report)
      [[ $# -ge 2 ]] || { echo "Missing value for --direct-report" >&2; exit 2; }
      direct_report_path="$2"
      shift 2
      ;;
    --scorecard-report)
      [[ $# -ge 2 ]] || { echo "Missing value for --scorecard-report" >&2; exit 2; }
      scorecard_report_path="$2"
      shift 2
      ;;
    --regression-report)
      [[ $# -ge 2 ]] || { echo "Missing value for --regression-report" >&2; exit 2; }
      regression_report_path="$2"
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

if [[ ! -f "${report_path}" ]]; then
  echo "Missing benchmark report: ${report_path}" >&2
  exit 1
fi

if [[ ! -f "${baseline_path}" ]]; then
  echo "Missing baseline config: ${baseline_path}" >&2
  exit 1
fi

mkdir -p "$(dirname "${scorecard_report_path}")"
mkdir -p "$(dirname "${regression_report_path}")"

python3 - "${report_path}" "${baseline_path}" "${direct_report_path}" "${scorecard_report_path}" "${regression_report_path}" <<'PY'
import json
import pathlib
import sys

report_path = pathlib.Path(sys.argv[1])
baseline_path = pathlib.Path(sys.argv[2])
direct_report_path = pathlib.Path(sys.argv[3])
scorecard_report_path = pathlib.Path(sys.argv[4])
regression_report_path = pathlib.Path(sys.argv[5])
project_root = baseline_path.parent.parent

with report_path.open("r", encoding="utf-8") as handle:
    report = json.load(handle)
with baseline_path.open("rb") as handle:
    import tomllib
    baseline = tomllib.load(handle)

metric_map = {
    "startup_ms": "startup_ms",
    "idle_rss_mb": "idle_rss_mb",
    "dispatch_latency_p95_ms": "dispatch_latency_p95_ms",
    "throughput_ops_per_sec": "throughput_ops_per_sec",
    "binary_size_mb": "binary_size_mb",
    "container_size_mb": "container_size_mb",
}
regression_metric_ids = (
    "startup_ms",
    "idle_rss_mb",
    "dispatch_latency_p95_ms",
    "throughput_ops_per_sec",
)

def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)

def load_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)

def get_metric(payload, metric_id):
    if not isinstance(payload, dict):
        return None
    if metric_id in payload:
        return payload.get(metric_id)
    for container_key in ("performance", "metrics", "vericlaw"):
        container = payload.get(container_key)
        if isinstance(container, dict) and metric_id in container:
            return container.get(metric_id)
    return None

def get_metric_availability(payload, metric_id):
    if not isinstance(payload, dict):
        return None
    availability = payload.get("metric_availability")
    if isinstance(availability, dict):
        metric_state = availability.get(metric_id)
        if isinstance(metric_state, dict):
            return metric_state
    return None

def metric_is_explicitly_unsupported(payload, metric_id):
    metric_state = get_metric_availability(payload, metric_id)
    return isinstance(metric_state, dict) and metric_state.get("supported") is False

def metric_collector(payload, metric_id):
    metric_state = get_metric_availability(payload, metric_id)
    if isinstance(metric_state, dict):
        collector = metric_state.get("collector")
        if isinstance(collector, str) and collector:
            return collector
    return "unknown"

def get_scorecard_value(payload, section, key):
    if not isinstance(payload, dict):
        return None
    section_payload = payload.get(section)
    if isinstance(section_payload, dict) and key in section_payload:
        return section_payload.get(key)
    scorecard = payload.get("scorecard")
    if isinstance(scorecard, dict):
        section_payload = scorecard.get(section)
        if isinstance(section_payload, dict) and key in section_payload:
            return section_payload.get(key)
    return None

direct_report = load_json(direct_report_path) if direct_report_path.is_file() else None

def run_v1_checks():
    quasar = report.get("vericlaw", {})
    errors = []
    for metric in baseline.get("edge_performance_metrics", []):
        metric_id = metric.get("id")
        report_key = metric_map.get(metric_id)
        if report_key is None:
            continue
        if metric_is_explicitly_unsupported(quasar, metric_id):
            errors.append(
                f"unsupported metric: {metric_id} collector={metric_collector(quasar, metric_id)}"
            )
            continue
        value = get_metric(quasar, metric_id)
        if value is None:
            errors.append(f"missing metric: {metric_id}")
            continue
        if not is_number(value):
            errors.append(f"non-numeric metric: {metric_id}={value!r}")
            continue
        slo_max = metric.get("quasar_slo_max")
        if is_number(slo_max) and value > slo_max:
            errors.append(f"SLO max exceeded: {metric_id} value={value} max={slo_max}")
        slo_min = metric.get("quasar_slo_min")
        if is_number(slo_min) and value < slo_min:
            errors.append(f"SLO min missed: {metric_id} value={value} min={slo_min}")
        if metric_id == "throughput_ops_per_sec" and value <= 0:
            errors.append("throughput_ops_per_sec must be positive")
    return errors

def run_v2_checks():
    errors = []
    regression_checks = []
    quasar = report.get("vericlaw", {})
    report_competitors = report.get("competitors", {})
    if not isinstance(report_competitors, dict):
        report_competitors = {}

    pass_fail_projects = baseline.get("pass_fail_compared_projects")
    if not isinstance(pass_fail_projects, list):
        pass_fail_projects = baseline.get("compared_projects", [])
    if not isinstance(pass_fail_projects, list):
        pass_fail_projects = []
    scorecard_only_projects = baseline.get("scorecard_only_projects", [])
    if not isinstance(scorecard_only_projects, list):
        scorecard_only_projects = []
    pass_fail_projects = [project for project in pass_fail_projects if isinstance(project, str) and project]
    scorecard_only_projects = [project for project in scorecard_only_projects if isinstance(project, str) and project]
    scorecard_only_set = set(scorecard_only_projects)
    pass_fail_projects = [project for project in pass_fail_projects if project not in scorecard_only_set]
    competitor_scorecards = baseline.get("competitor_scorecards", {})
    if not isinstance(competitor_scorecards, dict):
        competitor_scorecards = {}

    direct_projects = {}
    if direct_report is None:
        errors.append(
            f"missing direct harness report: {direct_report_path} (run: ./scripts/run_direct_competitor_harness.sh --quasar-report {report_path})"
        )
    else:
        schema_version = direct_report.get("schema_version")
        if schema_version != "competitive-v2-direct-harness":
            errors.append(
                f"unexpected direct harness schema: {schema_version!r} (expected 'competitive-v2-direct-harness')"
            )
        projects_payload = direct_report.get("projects")
        if not isinstance(projects_payload, dict):
            errors.append(f"invalid direct harness project map in {direct_report_path}")
        else:
            direct_projects = projects_payload
            direct_quasar = direct_projects.get("vericlaw")
            if isinstance(direct_quasar, dict):
                quasar = direct_quasar
            else:
                errors.append("missing direct-harness project payload: vericlaw")
            for project in ["vericlaw", *pass_fail_projects]:
                payload = direct_projects.get(project)
                if not isinstance(payload, dict):
                    errors.append(f"missing direct-harness project payload: {project}")
                    continue
                for metric_id in regression_metric_ids:
                    metric_value = get_metric(payload, metric_id)
                    if not is_number(metric_value):
                        errors.append(
                            f"missing direct-harness metric: {project}.{metric_id} (source: {direct_report_path})"
                        )

    competitor_payloads = {}
    for project in dict.fromkeys(pass_fail_projects + scorecard_only_projects):
        payload = None
        if isinstance(direct_projects.get(project), dict):
            payload = direct_projects.get(project)
        elif isinstance(report_competitors.get(project), dict):
            payload = report_competitors.get(project)
        else:
            rel_path = competitor_scorecards.get(project)
            if isinstance(rel_path, str) and rel_path:
                absolute_path = project_root / rel_path
                if absolute_path.is_file():
                    payload = load_json(absolute_path)
                elif project in pass_fail_projects:
                    errors.append(f"missing competitor scorecard file for {project}: {rel_path}")
        competitor_payloads[project] = payload
        if project in pass_fail_projects and payload is None:
            errors.append(f"missing required competitor scorecard: {project}")
        if project in scorecard_only_projects and payload is None:
            errors.append(f"missing scorecard-only competitor scorecard: {project}")

    for metric in baseline.get("edge_performance_metrics", []):
        metric_id = metric.get("id")
        report_key = metric_map.get(metric_id)
        if report_key is None:
            continue

        direction = metric.get("direction")
        ratio_max = metric.get("quasar_vs_competitor_ratio_max")
        ratio_min = metric.get("quasar_vs_competitor_ratio_min")
        slo_max = metric.get("quasar_slo_max")
        slo_min = metric.get("quasar_slo_min")
        value = get_metric(quasar, metric_id)
        metric_record = {
            "metric_id": metric_id,
            "direction": direction,
            "quasar_value": value if is_number(value) else None,
            "quasar_slo_max": slo_max if is_number(slo_max) else None,
            "quasar_slo_min": slo_min if is_number(slo_min) else None,
            "comparisons": [],
        }

        if metric_is_explicitly_unsupported(quasar, metric_id):
            errors.append(
                f"unsupported metric: {metric_id} collector={metric_collector(quasar, metric_id)}"
            )
            if metric_id in regression_metric_ids:
                metric_record["status"] = "fail"
                metric_record["failure_reason"] = "unsupported"
            regression_checks.append(metric_record)
            continue
        if value is None:
            errors.append(f"missing metric: {metric_id}")
            if metric_id in regression_metric_ids:
                metric_record["status"] = "fail"
                metric_record["failure_reason"] = "missing"
            regression_checks.append(metric_record)
            continue
        if not is_number(value):
            errors.append(f"non-numeric metric: {metric_id}={value!r}")
            if metric_id in regression_metric_ids:
                metric_record["status"] = "fail"
                metric_record["failure_reason"] = "non_numeric"
            regression_checks.append(metric_record)
            continue

        if is_number(slo_max) and value > slo_max:
            errors.append(f"SLO max exceeded: {metric_id} value={value} max={slo_max}")
        if is_number(slo_min) and value < slo_min:
            errors.append(f"SLO min missed: {metric_id} value={value} min={slo_min}")
        if metric_id == "throughput_ops_per_sec" and value <= 0:
            errors.append("throughput_ops_per_sec must be positive")

        if metric_id in regression_metric_ids:
            for project in pass_fail_projects:
                payload = competitor_payloads.get(project)
                comparison = {
                    "project": project,
                    "competitor_value": None,
                    "quasar_to_competitor_ratio": None,
                    "ratio_max": ratio_max if is_number(ratio_max) else None,
                    "ratio_min": ratio_min if is_number(ratio_min) else None,
                    "status": "pass",
                }
                if payload is None:
                    comparison["status"] = "fail"
                    comparison["failure_reason"] = "missing_competitor_payload"
                    metric_record["comparisons"].append(comparison)
                    continue
                if metric_is_explicitly_unsupported(payload, metric_id):
                    errors.append(
                        f"unsupported competitor metric: {project}.{metric_id} collector={metric_collector(payload, metric_id)}"
                    )
                    comparison["status"] = "fail"
                    comparison["failure_reason"] = "unsupported_competitor_metric"
                    metric_record["comparisons"].append(comparison)
                    continue
                competitor_value = get_metric(payload, metric_id)
                if not is_number(competitor_value):
                    errors.append(f"missing competitor metric: {project}.{metric_id}")
                    comparison["status"] = "fail"
                    comparison["failure_reason"] = "missing_competitor_metric"
                    metric_record["comparisons"].append(comparison)
                    continue
                comparison["competitor_value"] = competitor_value
                if competitor_value <= 0:
                    errors.append(f"non-positive competitor metric: {project}.{metric_id}={competitor_value}")
                    comparison["status"] = "fail"
                    comparison["failure_reason"] = "non_positive_competitor_metric"
                    metric_record["comparisons"].append(comparison)
                    continue
                comparison["quasar_to_competitor_ratio"] = value / competitor_value

                if is_number(ratio_max):
                    if direction == "lower_is_better":
                        gate_ratio = value / competitor_value
                    else:
                        gate_ratio = competitor_value / value if value > 0 else float("inf")
                    comparison["ratio_check_max_observed"] = gate_ratio
                    if gate_ratio > ratio_max:
                        errors.append(
                            f"ratio max exceeded: {metric_id} quasar={value} {project}={competitor_value} gate_ratio={gate_ratio:.3f} max={ratio_max}"
                        )
                        comparison["status"] = "fail"
                        comparison["failure_reason"] = "ratio_max_exceeded"
                if is_number(ratio_min):
                    if direction == "higher_is_better":
                        gate_ratio = value / competitor_value
                    else:
                        gate_ratio = competitor_value / value if value > 0 else 0.0
                    comparison["ratio_check_min_observed"] = gate_ratio
                    if gate_ratio < ratio_min:
                        errors.append(
                            f"ratio min missed: {metric_id} quasar={value} {project}={competitor_value} gate_ratio={gate_ratio:.3f} min={ratio_min}"
                        )
                        comparison["status"] = "fail"
                        comparison["failure_reason"] = "ratio_min_missed"

                metric_record["comparisons"].append(comparison)

        if metric_id in regression_metric_ids:
            metric_record["status"] = (
                "fail"
                if any(c.get("status") == "fail" for c in metric_record["comparisons"])
                or (is_number(slo_max) and value > slo_max)
                or (is_number(slo_min) and value < slo_min)
                or (metric_id == "throughput_ops_per_sec" and value <= 0)
                else "pass"
            )
            regression_checks.append(metric_record)

    quasar_scorecard = baseline.get("quasar_scorecard", {})
    if not isinstance(quasar_scorecard, dict):
        quasar_scorecard = {}
    quasar_feature = quasar_scorecard.get("feature_parity", {})
    if not isinstance(quasar_feature, dict):
        quasar_feature = {}
    quasar_deployment = quasar_scorecard.get("deployment_maturity", {})
    if not isinstance(quasar_deployment, dict):
        quasar_deployment = {}
    quasar_security_fallback = quasar_scorecard.get("security_non_regression", {})
    if not isinstance(quasar_security_fallback, dict):
        quasar_security_fallback = {}

    for counter in baseline.get("feature_parity_counters", []):
        counter_id = counter.get("id")
        quasar_value = quasar_feature.get(counter_id)
        if not is_number(quasar_value):
            errors.append(f"missing quasar feature parity value: {counter_id}")
            continue
        quasar_min = counter.get("quasar_min")
        if is_number(quasar_min) and quasar_value < quasar_min:
            errors.append(f"feature parity minimum missed: {counter_id} value={quasar_value} min={quasar_min}")
        diff_min = counter.get("quasar_minus_competitor_min")
        if not is_number(diff_min):
            continue
        for project in pass_fail_projects:
            payload = competitor_payloads.get(project)
            if payload is None:
                continue
            competitor_value = get_scorecard_value(payload, "feature_parity", counter_id)
            if not is_number(competitor_value):
                errors.append(f"missing competitor feature parity value: {project}.{counter_id}")
                continue
            delta = quasar_value - competitor_value
            if delta < diff_min:
                errors.append(
                    f"feature parity delta missed: {counter_id} quasar-{project}={delta} min={diff_min}"
                )

    for check in baseline.get("deployment_maturity_checks", []):
        check_id = check.get("id")
        check_type = check.get("check_type")
        quasar_value = quasar_deployment.get(check_id)
        if check_type == "bool":
            expected = check.get("quasar_expected")
            if not isinstance(quasar_value, bool):
                errors.append(f"missing quasar deployment bool: {check_id}")
            elif isinstance(expected, bool) and quasar_value != expected:
                errors.append(f"quasar deployment mismatch: {check_id} value={quasar_value} expected={expected}")
            competitor_expected = check.get("competitor_expected")
            for project in pass_fail_projects:
                payload = competitor_payloads.get(project)
                if payload is None:
                    continue
                competitor_value = get_scorecard_value(payload, "deployment_maturity", check_id)
                if isinstance(competitor_expected, bool):
                    if not isinstance(competitor_value, bool):
                        errors.append(f"missing competitor deployment bool: {project}.{check_id}")
                    elif competitor_value != competitor_expected:
                        errors.append(
                            f"competitor deployment mismatch: {project}.{check_id} value={competitor_value} expected={competitor_expected}"
                        )
        elif check_type == "count":
            if not is_number(quasar_value):
                errors.append(f"missing quasar deployment count: {check_id}")
                continue
            quasar_min = check.get("quasar_min")
            if is_number(quasar_min) and quasar_value < quasar_min:
                errors.append(f"quasar deployment minimum missed: {check_id} value={quasar_value} min={quasar_min}")
            competitor_min = check.get("competitor_min")
            for project in pass_fail_projects:
                payload = competitor_payloads.get(project)
                if payload is None:
                    continue
                competitor_value = get_scorecard_value(payload, "deployment_maturity", check_id)
                if is_number(competitor_min):
                    if not is_number(competitor_value):
                        errors.append(f"missing competitor deployment count: {project}.{check_id}")
                    elif competitor_value < competitor_min:
                        errors.append(
                            f"competitor deployment minimum missed: {project}.{check_id} value={competitor_value} min={competitor_min}"
                        )

    security_source = baseline.get("security_defaults_source", {})
    security_defaults = {}
    if isinstance(security_source, dict):
        source_path = security_source.get("path")
        source_table = security_source.get("table")
        if isinstance(source_path, str) and source_path:
            absolute_path = project_root / source_path
            if absolute_path.is_file():
                with absolute_path.open("rb") as handle:
                    source_doc = tomllib.load(handle)
                if isinstance(source_table, str) and source_table:
                    source_doc = source_doc.get(source_table, {})
                if isinstance(source_doc, dict):
                    security_defaults.update(source_doc)
                else:
                    errors.append(f"invalid security defaults table: {source_table}")
            else:
                errors.append(f"missing security defaults source: {source_path}")

    for check in baseline.get("security_non_regression_checks", []):
        check_id = check.get("id")
        source_key = check.get("source_key")
        expected = check.get("expected")
        value = security_defaults.get(source_key, quasar_security_fallback.get(source_key))
        if value is None:
            errors.append(f"missing security non-regression source key: {source_key}")
            continue
        if value != expected:
            errors.append(f"security non-regression mismatch: {check_id} value={value} expected={expected}")

    comparative_dimensions = {}
    for project in dict.fromkeys(pass_fail_projects + scorecard_only_projects):
        payload = competitor_payloads.get(project)
        role = "scorecard_only_reference" if project in scorecard_only_set else "pass_fail_peer"
        feature_comparison = {}
        for counter in baseline.get("feature_parity_counters", []):
            counter_id = counter.get("id")
            if not isinstance(counter_id, str) or not counter_id:
                continue
            quasar_value = quasar_feature.get(counter_id)
            competitor_value = get_scorecard_value(payload, "feature_parity", counter_id)
            entry = {"vericlaw": quasar_value, project: competitor_value}
            if is_number(quasar_value) and is_number(competitor_value):
                entry["delta_vericlaw_minus_project"] = quasar_value - competitor_value
            feature_comparison[counter_id] = entry
        deployment_comparison = {}
        for check in baseline.get("deployment_maturity_checks", []):
            check_id = check.get("id")
            if not isinstance(check_id, str) or not check_id:
                continue
            deployment_comparison[check_id] = {
                "vericlaw": quasar_deployment.get(check_id),
                project: get_scorecard_value(payload, "deployment_maturity", check_id),
            }
        comparative_dimensions[project] = {
            "role": role,
            "feature_parity": feature_comparison,
            "deployment_maturity": deployment_comparison,
        }

    scorecard_snapshot = {
        "generated_at": report.get("generated_at"),
        "baseline_id": baseline.get("baseline_id"),
        "primary_project": baseline.get("primary_project", "vericlaw"),
        "pass_fail_projects": pass_fail_projects,
        "scorecard_only_projects": scorecard_only_projects,
        "vericlaw": {
            "feature_parity": quasar_feature,
            "deployment_maturity": quasar_deployment,
            "security_non_regression": quasar_security_fallback,
        },
        "comparative_dimensions": comparative_dimensions,
    }

    return errors, scorecard_snapshot, regression_checks, pass_fail_projects, scorecard_only_projects

baseline_version = baseline.get("version", 1)
scorecard_snapshot = None
regression_checks = []
pass_fail_projects = []
scorecard_only_projects = []
if baseline_version >= 2:
    (
        errors,
        scorecard_snapshot,
        regression_checks,
        pass_fail_projects,
        scorecard_only_projects,
    ) = run_v2_checks()
else:
    errors = run_v1_checks()

if scorecard_snapshot is not None:
    scorecard_report_path.parent.mkdir(parents=True, exist_ok=True)
    scorecard_report_path.write_text(
        json.dumps(scorecard_snapshot, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"competitive-scorecard: {scorecard_report_path}")

regression_payload = {
    "generated_at": report.get("generated_at"),
    "baseline_id": baseline.get("baseline_id"),
    "baseline_version": baseline_version,
    "status": "fail" if errors else "pass",
    "benchmark_report": str(report_path),
    "direct_harness_report": str(direct_report_path),
    "scorecard_report": str(scorecard_report_path),
    "regression_metrics": list(regression_metric_ids),
    "pass_fail_projects": pass_fail_projects,
    "scorecard_only_projects": scorecard_only_projects,
    "checks": regression_checks,
    "errors": errors,
}
regression_report_path.parent.mkdir(parents=True, exist_ok=True)
regression_report_path.write_text(
    json.dumps(regression_payload, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
print(f"competitive-regression-report: {regression_report_path}")

if errors:
    print("competitive-baseline: FAIL")
    for error in errors:
        print(f"  - {error}")
    print("  - action: run make competitive-regression-gate")
    print(f"  - action: inspect {regression_report_path}")
    raise SystemExit(1)

print("competitive-baseline: PASS")
PY
