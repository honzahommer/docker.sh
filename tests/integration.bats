#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# Integration tests for docker.sh
# ---------------------------------------------------------------------------
# These tests hit the real Docker daemon and GitHub Container Registry.
# Required env vars:
#   GHCR_USERNAME  — GitHub username (or github-actions bot)
#   GHCR_TOKEN     — A token with packages:read (GITHUB_TOKEN works in CI)
# ---------------------------------------------------------------------------

SCRIPT="$BATS_TEST_DIRNAME/../docker.sh"

setup() {
  if [[ -z "${GHCR_USERNAME:-}" || -z "${GHCR_TOKEN:-}" ]]; then
    skip "GHCR_USERNAME / GHCR_TOKEN not set — skipping integration tests"
  fi
}

# ---- GHCR login -----------------------------------------------------------

@test "login to GitHub Container Registry succeeds" {
  run bash "$SCRIPT" \
    -u "$GHCR_USERNAME" \
    -p "$GHCR_TOKEN" \
    -r ghcr.io \
    info
  [ "$status" -eq 0 ]
  # info should produce some docker output (e.g. "Server Version")
  [[ "$output" == *"Server"* ]] || [[ "$output" == *"Client"* ]] || [[ "$output" == *"docker"* ]]
}

# ---- docker info via DOCKER_COMMAND ----------------------------------------

@test "docker.sh runs 'info' via DOCKER_COMMAND env var" {
  export DOCKER_USERNAME="$GHCR_USERNAME"
  export DOCKER_PASSWORD="$GHCR_TOKEN"
  export DOCKER_REGISTRY="ghcr.io"
  export DOCKER_COMMAND="info"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Server"* ]] || [[ "$output" == *"Client"* ]] || [[ "$output" == *"docker"* ]]
}

# ---- dry-run against GHCR -------------------------------------------------

@test "dry-run against GHCR shows correct registry" {
  run bash "$SCRIPT" \
    -u "$GHCR_USERNAME" \
    -p "$GHCR_TOKEN" \
    -r ghcr.io \
    -d info
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghcr.io"* ]]
  [[ "$output" == *"[dry-run] docker info"* ]]
}

# ---- quiet login -----------------------------------------------------------

@test "quiet login to GHCR suppresses info output" {
  run bash "$SCRIPT" \
    -u "$GHCR_USERNAME" \
    -p "$GHCR_TOKEN" \
    -r ghcr.io \
    -q info
  [ "$status" -eq 0 ]
  [[ "$output" != *"[INFO]"* ]]
}

# ---- bad credentials ------------------------------------------------------

@test "login to GHCR with bad credentials fails" {
  run bash "$SCRIPT" \
    -u "bogus-user-does-not-exist" \
    -p "not-a-real-token" \
    -r ghcr.io \
    info
  [ "$status" -ne 0 ]
  [[ "$output" == *"docker login failed"* ]]
}
