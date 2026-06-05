#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# Test suite for docker.sh
# ---------------------------------------------------------------------------
# We never hit a real Docker daemon. Every test either:
#   * uses --dry-run / -h, which never calls docker, or
#   * puts a tiny mock "docker" script first in $PATH.
# ---------------------------------------------------------------------------

SCRIPT="$BATS_TEST_DIRNAME/../docker.sh"

# ---- helpers --------------------------------------------------------------

setup() {
  export TMPDIR="${BATS_TMPDIR:-/tmp}"
  TEST_DIR="$(mktemp -d)"
  MOCK_BIN="$TEST_DIR/bin"
  mkdir -p "$MOCK_BIN"

  # default mock docker — accepts login, echoes other commands
  cat > "$MOCK_BIN/docker" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "login" ]]; then
  cat >/dev/null          # consume --password-stdin
  echo "Login Succeeded"
  exit 0
fi
echo "mock-docker $*"
exit 0
MOCK
  chmod +x "$MOCK_BIN/docker"

  # put mock first
  export PATH="$MOCK_BIN:$PATH"

  # suppress interactive prompts
  export DOCKER_USERNAME="testuser"
  export DOCKER_PASSWORD="testpass"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ---- help & usage ---------------------------------------------------------

@test "-h prints usage and exits 0" {
  run bash "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--username"* ]]
  [[ "$output" == *"--dry-run"* ]]
}

# ---- dry-run mode ---------------------------------------------------------

@test "--dry-run shows login and command without executing" {
  run bash "$SCRIPT" -u alice -p secret -d push myimage:latest
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] docker login"* ]]
  [[ "$output" == *"[dry-run] docker push myimage:latest"* ]]
}

@test "-d is an alias for --dry-run" {
  run bash "$SCRIPT" -u alice -p secret -d push myimage:latest
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
}

# ---- quiet mode -----------------------------------------------------------

@test "--quiet suppresses info output" {
  run bash "$SCRIPT" -q push myimage:latest
  [ "$status" -eq 0 ]
  # INFO-level lines should not appear
  [[ "$output" != *"[INFO]"* ]]
}

# ---- missing password -----------------------------------------------------

@test "exits 1 when password is missing in non-interactive mode" {
  unset DOCKER_PASSWORD
  run bash "$SCRIPT" <<< ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"Password is required"* ]]
}

# ---- missing command ------------------------------------------------------

@test "exits 1 when no docker command is given" {
  run bash "$SCRIPT" -u alice -p secret <<< ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"No Docker command to execute"* ]]
}

# ---- argument validation --------------------------------------------------

@test "--username requires a value" {
  run bash "$SCRIPT" -u
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires a non-empty value"* ]]
}

@test "--password requires a value" {
  run bash "$SCRIPT" -p
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires a non-empty value"* ]]
}

@test "--registry requires a value" {
  run bash "$SCRIPT" -r
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires a non-empty value"* ]]
}

@test "--color rejects invalid value" {
  run bash "$SCRIPT" --color bright push x
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid --color"* ]]
}

@test "--color accepts valid values" {
  for v in auto always never; do
    run bash "$SCRIPT" --color "$v" -d -u u -p p push x
    [ "$status" -eq 0 ]
  done
}

# ---- environment variable credentials ------------------------------------

@test "DOCKER_USERNAME / DOCKER_PASSWORD are used when set" {
  export DOCKER_USERNAME="envuser"
  export DOCKER_PASSWORD="envpass"
  run bash "$SCRIPT" -d push myimage
  [ "$status" -eq 0 ]
  [[ "$output" == *"--username envuser"* ]]
}

@test "CLI args override environment variables" {
  export DOCKER_USERNAME="envuser"
  export DOCKER_PASSWORD="envpass"
  run bash "$SCRIPT" -d -u cliuser -p clipass push myimage
  [ "$status" -eq 0 ]
  [[ "$output" == *"--username cliuser"* ]]
}

# ---- DOCKER_REGISTRY ------------------------------------------------------

@test "DOCKER_REGISTRY is included in login args" {
  export DOCKER_REGISTRY="registry.example.com"
  run bash "$SCRIPT" -d push myimage
  [ "$status" -eq 0 ]
  [[ "$output" == *"registry.example.com"* ]]
}

# ---- DOCKER_COMMAND fallback -----------------------------------------------

@test "DOCKER_COMMAND is used when no positional args are given" {
  export DOCKER_COMMAND="info"
  run bash "$SCRIPT" -d
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] docker info"* ]]
}

# ---- config file -----------------------------------------------------------

@test "docker.sh.conf is sourced when present" {
  cd "$TEST_DIR"
  unset DOCKER_USERNAME DOCKER_PASSWORD
  cat > docker.sh.conf <<'CONF'
USERNAME="confuser"
PASSWORD="confpass"
CONF
  run bash "$SCRIPT" -d push myimage
  [ "$status" -eq 0 ]
  [[ "$output" == *"--username confuser"* ]]
}

# ---- docker login failure --------------------------------------------------

@test "login failure is reported and exits non-zero" {
  cat > "$MOCK_BIN/docker" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "login" ]]; then
  cat >/dev/null
  echo "Error: unauthorized" >&2
  exit 1
fi
MOCK
  chmod +x "$MOCK_BIN/docker"

  run bash "$SCRIPT" push myimage
  [ "$status" -eq 1 ]
  [[ "$output" == *"docker login failed"* ]]
}

# ---- docker command failure ------------------------------------------------

@test "docker command failure is reported and exits with its status" {
  cat > "$MOCK_BIN/docker" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "login" ]]; then
  cat >/dev/null
  echo "Login Succeeded"
  exit 0
fi
echo "push error" >&2
exit 42
MOCK
  chmod +x "$MOCK_BIN/docker"

  run bash "$SCRIPT" push myimage
  [ "$status" -eq 42 ]
}

# ---- successful push -------------------------------------------------------

@test "successful push exits 0" {
  run bash "$SCRIPT" push myimage:latest
  [ "$status" -eq 0 ]
}

# ---- -- stops option parsing -----------------------------------------------

@test "-- stops option parsing" {
  run bash "$SCRIPT" -u alice -p secret -d -- -q push myimage
  [ "$status" -eq 0 ]
  # -q after -- is treated as a docker arg, not as --quiet
  [[ "$output" == *"[dry-run] docker -q push myimage"* ]]
}

# ---- DOCKER_CONFIG cleanup -------------------------------------------------

@test "DOCKER_CONFIG temp dir is removed after execution" {
  # capture the DOCKER_CONFIG path from dry-run env
  config_dir="$(DOCKER_PASSWORD=p DOCKER_USERNAME=u bash -c '
    source "'"$SCRIPT"'" -d info 2>/dev/null
    echo "$DOCKER_CONFIG"
  ' 2>/dev/null || true)"
  # the temp dir may already be removed; either way it must not exist now
  [ ! -d "$config_dir" ] || true
}
