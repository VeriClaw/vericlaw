#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
secure_defaults_template="${project_root}/config/bootstrap_secure_defaults.env"
secure_defaults_local="${project_root}/config/bootstrap.local.env"
security_slos_file="${project_root}/config/security_slos.toml"

usage() {
  cat <<'EOF'
Usage: ./scripts/bootstrap_toolchain.sh [--install] [--validate]

Checks for local Ada/SPARK prerequisites and prints platform-specific guidance.
Use --install to attempt package-manager installs where supported.
Use --validate for lightweight syntax + secure-default checks only.
EOF
}

collect_missing_tools() {
  missing_tools=()
  for tool in gprbuild gnatprove; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing_tools+=("$tool")
    fi
  done
}

detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    *) echo "unsupported" ;;
  esac
}

detect_pkg_manager() {
  for manager in brew apt-get dnf yum zypper pacman; do
    if command -v "$manager" >/dev/null 2>&1; then
      echo "$manager"
      return
    fi
  done
  echo "none"
}

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    return 127
  fi
}

install_library_deps() {
  local manager="$1"

  echo "Installing C library dependencies (libcurl, libsqlite3)..."
  case "$manager" in
    brew)
      brew install curl sqlite || echo "Homebrew install failed for curl/sqlite." >&2
      ;;
    apt-get)
      run_as_root apt-get install -y libcurl4-openssl-dev libsqlite3-dev \
        || echo "apt install failed for libcurl/libsqlite3." >&2
      ;;
    dnf|yum)
      run_as_root "$manager" install -y libcurl-devel sqlite-devel \
        || echo "Package install failed for libcurl/sqlite." >&2
      ;;
    *)
      echo "Install libcurl-dev and libsqlite3-dev manually for your platform." >&2
      ;;
  esac
}

install_alire_crates() {
  if ! command -v alr >/dev/null 2>&1; then
    echo "Alire (alr) not found; skipping Ada library crate install." >&2
    return
  fi

  echo "Installing Ada library crates via Alire (gnatcoll, gnatcoll_sqlite, aws)..."
  alr with gnatcoll      || echo "alr: gnatcoll crate install failed." >&2
  alr with gnatcoll_sqlite || echo "alr: gnatcoll_sqlite crate install failed." >&2
  alr with aws           || echo "alr: aws crate install failed." >&2
}

install_with_brew() {
  if ! command -v gprbuild >/dev/null 2>&1; then
    echo "Installing gprbuild via Homebrew..."
    brew install gprbuild || echo "Homebrew install failed for gprbuild." >&2
  fi

  if ! command -v alr >/dev/null 2>&1; then
    echo "Installing Alire via Homebrew (used to provision GNAT/SPARK toolchains)..."
    brew install alire || echo "Homebrew install failed for alire." >&2
  fi

  if ! command -v gnatprove >/dev/null 2>&1; then
    echo "gnatprove is still missing; follow Alire/AdaCore setup guidance below." >&2
  fi

  install_library_deps "brew"
  install_alire_crates
}

install_with_apt() {
  if ! run_as_root true >/dev/null 2>&1; then
    echo "Cannot run apt-get install without root/sudo privileges." >&2
    return 1
  fi

  echo "Installing GNAT + gprbuild via apt..."
  run_as_root apt-get update
  run_as_root apt-get install -y gnat gprbuild || echo "apt install failed for gnat/gprbuild." >&2

  if command -v apt-cache >/dev/null 2>&1; then
    if apt-cache show gnatprove >/dev/null 2>&1; then
      echo "Installing gnatprove package..."
      run_as_root apt-get install -y gnatprove || echo "apt install failed for gnatprove." >&2
    elif apt-cache show spark2014 >/dev/null 2>&1; then
      echo "Installing SPARK package (spark2014)..."
      run_as_root apt-get install -y spark2014 || echo "apt install failed for spark2014." >&2
    fi
  fi

  install_library_deps "apt-get"
  install_alire_crates
}

print_guidance() {
  local os="$1"
  local manager="$2"

  echo "Detected OS: $os"
  echo "Detected package manager: $manager"
  echo "Missing tools: ${missing_tools[*]}"
  echo
  echo "Host setup guidance:"

  case "$manager" in
    brew)
      cat <<'EOF'
  brew install gprbuild alire curl sqlite
  # Then: alr with gnatcoll gnatcoll_sqlite aws
  # Run `alr` and follow its toolchain selection prompts (GNAT + SPARK).
EOF
      ;;
    apt-get)
      cat <<'EOF'
  sudo apt-get update
  sudo apt-get install -y gnat gprbuild libcurl4-openssl-dev libsqlite3-dev
  # SPARK prover package name varies by distro:
  #   sudo apt-get install -y gnatprove
  #   or sudo apt-get install -y spark2014
  # Ada library crates (requires Alire):
  #   alr with gnatcoll gnatcoll_sqlite aws
EOF
      ;;
    dnf|yum|zypper|pacman)
      cat <<'EOF'
  Install GNAT + gprbuild with your distro package manager, then install SPARK (gnatprove).
  Also install: libcurl-devel sqlite-devel
  Package names vary by distribution; prefer official AdaCore/Alire toolchain instructions.
  Ada library crates (requires Alire): alr with gnatcoll gnatcoll_sqlite aws
EOF
      ;;
    *)
      cat <<'EOF'
  Install GNAT (with gprbuild) and SPARK (gnatprove) using your platform's official instructions.
  Also install: libcurl-dev libsqlite3-dev
  Ada library crates (requires Alire): alr with gnatcoll gnatcoll_sqlite aws
EOF
      ;;
  esac

  echo
  echo "Container fallback (no host toolchain required):"
  echo "  ./scripts/run_container_ci.sh check"
}

run_syntax_checks() {
  bash -n \
    "${project_root}/scripts/check_toolchain.sh" \
    "${project_root}/scripts/bootstrap_toolchain.sh" \
    "${project_root}/scripts/check_operator_console.sh" \
    "${project_root}/scripts/serve_operator_console.sh"
}

require_setting() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local value

  value="$(awk -F= -v wanted="$key" '$1 == wanted { gsub(/[[:space:]]/, "", $2); print $2 }' "$file" | tail -n1)"
  if [[ "$value" != "$expected" ]]; then
    echo "Expected ${key}=${expected} in ${file}" >&2
    return 1
  fi
}

validate_secure_defaults_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "Missing secure defaults file: $file" >&2
    return 1
  fi

  require_setting "$file" "OPERATOR_CONSOLE_HOST" "127.0.0.1"
  require_setting "$file" "OPERATOR_CONSOLE_ALLOW_NON_LOOPBACK" "0"
  require_setting "$file" "QUASAR_DENY_BY_DEFAULT" "1"
  require_setting "$file" "QUASAR_ALLOW_PUBLIC_BIND" "0"
  require_setting "$file" "QUASAR_PAIRING_REQUIRED" "1"
}

validate_security_policy_defaults() {
  if [[ ! -f "$security_slos_file" ]]; then
    echo "Missing security baseline file: $security_slos_file" >&2
    return 1
  fi

  grep -Eq '^empty_allowlist_denies_all = true$' "$security_slos_file" \
    || { echo "Expected empty_allowlist_denies_all = true in ${security_slos_file}" >&2; return 1; }
  grep -Eq '^pairing_required_by_default = true$' "$security_slos_file" \
    || { echo "Expected pairing_required_by_default = true in ${security_slos_file}" >&2; return 1; }
  grep -Eq '^public_bind_default = false$' "$security_slos_file" \
    || { echo "Expected public_bind_default = false in ${security_slos_file}" >&2; return 1; }
}

initialize_secure_defaults() {
  if [[ -f "$secure_defaults_local" ]]; then
    echo "Secure defaults already initialized: ${secure_defaults_local}"
  else
    cp "$secure_defaults_template" "$secure_defaults_local"
    echo "Initialized secure defaults: ${secure_defaults_local}"
  fi

  validate_secure_defaults_file "$secure_defaults_local"
}

print_security_posture() {
  echo "Secure bootstrap posture: loopback-first networking + deny-by-default policy."
}

print_next_steps() {
  local toolchain_ready="$1"

  echo
  echo "Next steps:"
  echo "  1) Review ${secure_defaults_local} (loopback-first + deny-by-default defaults)."
  if [[ "$toolchain_ready" -eq 1 ]]; then
    echo "  2) Run make check for build/proof validation."
  else
    echo "  2) Install missing tools (or use ./scripts/run_container_ci.sh check)."
  fi
  echo "  3) Keep local serving loopback-first: ./scripts/serve_operator_console.sh --host 127.0.0.1"
}

install_mode=0
validate_mode=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      install_mode=1
      shift
      ;;
    --validate)
      validate_mode=1
      shift
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

run_syntax_checks
validate_security_policy_defaults
validate_secure_defaults_file "$secure_defaults_template"

if [[ "$validate_mode" -eq 1 ]]; then
  echo "Bootstrap validation checks passed."
  exit 0
fi

print_security_posture
initialize_secure_defaults

collect_missing_tools
if [[ ${#missing_tools[@]} -eq 0 ]]; then
  echo "Ada/SPARK toolchain already available."
  print_next_steps 1
  exit 0
fi

if [[ "$install_mode" -eq 1 ]]; then
  os="$(detect_os)"
  manager="$(detect_pkg_manager)"
  case "$manager" in
    brew)
      install_with_brew
      ;;
    apt-get)
      install_with_apt || true
      ;;
    *)
      echo "Automatic install is not implemented for package manager: $manager" >&2
      ;;
  esac
fi

collect_missing_tools
if [[ ${#missing_tools[@]} -eq 0 ]]; then
  echo "Ada/SPARK toolchain bootstrap completed successfully."
  print_next_steps 1
  exit 0
fi

os="$(detect_os)"
manager="$(detect_pkg_manager)"
print_guidance "$os" "$manager" >&2
print_next_steps 0 >&2
exit 1
