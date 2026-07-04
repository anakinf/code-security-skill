#!/usr/bin/env bash
# Lightweight multi-stack security scanner for code-security-audit skill.
# Usage: bash scan.sh [PROJECT_ROOT]
set -uo pipefail

ROOT="${1:-.}"
cd "$ROOT" || exit 1

echo "=== Code Security Scan ==="
echo "Root: $(pwd)"
echo "Date: $(date -Iseconds 2>/dev/null || date)"
echo

run_if() {
  local name="$1"
  shift
  if command -v "$1" >/dev/null 2>&1; then
    echo "--- $name ---"
    "$@" 2>&1 || echo "[$name exited non-zero]"
    echo
  else
    echo "--- $name --- SKIPPED (command not found: $1)"
    echo
  fi
}

EXCLUDES="-x ./venv,./.venv,./node_modules,./.git,./dist,./build,./target"

# Python
if [ -f requirements.txt ] || [ -f pyproject.toml ] || find . -maxdepth 3 -name '*.py' -print -quit 2>/dev/null | grep -q .; then
  echo ">> Detected: Python"
  run_if "Bandit" bandit -r . -ll $EXCLUDES
  if [ -f requirements.txt ]; then
    run_if "pip-audit" pip-audit -r requirements.txt
  else
    run_if "pip-audit" pip-audit
  fi
  run_if "Semgrep OWASP" semgrep --config=registry/owasp-top-ten --quiet .
fi

# Node
if [ -f package.json ]; then
  echo ">> Detected: Node.js"
  if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
    run_if "npm audit" npm audit --audit-level=high
  elif [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
    run_if "pnpm audit" pnpm audit --audit-level high
  elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
    run_if "yarn audit" yarn audit --level high
  else
    echo "--- npm audit --- SKIPPED (no lockfile)"
    echo
  fi
fi

# Go
if [ -f go.mod ]; then
  echo ">> Detected: Go"
  if command -v govulncheck >/dev/null 2>&1; then
    run_if "govulncheck" govulncheck ./...
  else
    echo "--- govulncheck --- SKIPPED (install: go install golang.org/x/vuln/cmd/govulncheck@latest)"
    echo
  fi
fi

# Java hint
if [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  echo ">> Detected: Java — run OWASP dependency-check via Maven/Gradle in CI"
  echo
fi

# .NET
if find . -maxdepth 4 \( -name '*.csproj' -o -name '*.sln' \) -print -quit 2>/dev/null | grep -q .; then
  echo ">> Detected: .NET"
  run_if "dotnet vulnerable packages" dotnet list package --vulnerable --include-transitive
  run_if "dotnet deprecated packages" dotnet list package --deprecated
fi

# PHP
if [ -f composer.json ]; then
  echo ">> Detected: PHP"
  run_if "composer audit" composer audit
  run_if "composer validate" composer validate --no-check-publish
fi

# Trivy filesystem
run_if "Trivy FS" trivy fs --severity HIGH,CRITICAL --scanners vuln,secret --exit-code 0 .

# Grep hints (no fail)
echo "--- Secret pattern grep (manual review) ---"
if command -v rg >/dev/null 2>&1; then
  rg -n --glob '!.git' --glob '!node_modules' --glob '!venv' --glob '!.venv' \
    -e 'AKIA[0-9A-Z]{16}' -e 'password\s*=\s*["'"'"'][^'"'"'"']+["'"'"']' \
    -e 'api[_-]?key\s*=\s*["'"'"'][^'"'"'"']+["'"'"']' \
    -e 'BEGIN (RSA |OPENSSH )?PRIVATE KEY' \
    -e 'shell=True|ProcessBuilder|exec\.Command|shell_exec|passthru|unserialize\(|BinaryFormatter|dangerouslySetInnerHTML|v-html|innerHTML' \
    . 2>/dev/null | head -50 || true
else
  grep -rEn 'AKIA[0-9A-Z]{16}|BEGIN PRIVATE KEY|shell=True|shell_exec|passthru|unserialize\(' . \
    --exclude-dir={.git,node_modules,venv,.venv} 2>/dev/null | head -20 || true
fi
echo

echo "=== Scan complete ==="
echo "Review automation.md for CI integration. Manual audit still required."
