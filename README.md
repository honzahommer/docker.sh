# docker.sh

A Bash wrapper around the `docker` CLI that handles one-shot login, runs a Docker command, and automatically cleans up stored credentials on exit.

## Features

- Temporary credential storage (`DOCKER_CONFIG` in a `mktemp -d` directory, removed via `trap`)
- Multiple credential sources with clear precedence
- Interactive prompts when credentials or command are not provided
- Dry-run mode (`-d`) to preview commands without executing
- Quiet mode (`-q`) to suppress informational output
- Command output and exit status captured in `CMD_OUTPUT` / `CMD_STATUS`

## Installation

```bash
curl -O https://example.com/docker.sh   # or copy the script manually
chmod +x docker.sh
```

## Usage

```
docker.sh [OPTIONS] [COMMANDS...]
```

### Options

| Flag | Long | Description |
|------|------|-------------|
| `-u` | `--username` | Username (defaults to `$USER`) |
| `-p` | `--password` | Password |
| `-r` | `--registry` | Registry (defaults to Docker Hub) |
| `-d` | `--dry-run` | Print commands instead of executing them |
| `-q` | `--quiet` | Suppress informational output |
| `-h` | | Show help and exit |

### Examples

```bash
# Push an image to Docker Hub
./docker.sh -u alice -p s3cret push myimage:latest

# Pull from a private registry
./docker.sh -u alice -p s3cret -r registry.example.com pull registry.example.com/myimage:v1

# Dry-run to see what would happen
./docker.sh -u alice -p s3cret -d push myimage:latest

# Quiet mode (login + push, minimal output)
./docker.sh -u alice -p s3cret -q push myimage:latest

# Interactive — prompts for username, password, and command
./docker.sh
```

## Credential Precedence

Values are resolved in the following order (highest wins):

| Priority | Source |
|----------|--------|
| 1 | Command-line arguments (`-u`, `-p`, `-r`) |
| 2 | Environment variables (`DOCKER_USERNAME`, `DOCKER_PASSWORD`, `DOCKER_REGISTRY`) |
| 3 | Config file (`docker.sh.conf` in the current directory) |
| 4 | Interactive prompt |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `DOCKER_USERNAME` | Login username |
| `DOCKER_PASSWORD` | Login password |
| `DOCKER_REGISTRY` | Registry URL |
| `DOCKER_COMMAND` | Fallback Docker command when none is passed as arguments |

```bash
export DOCKER_USERNAME=alice
export DOCKER_PASSWORD=s3cret
./docker.sh push myimage:latest
```

### Config File

If a file named `docker.sh.conf` exists in the current working directory, it is sourced before any other resolution. It may set `USERNAME`, `PASSWORD`, and/or `REGISTRY`:

```bash
# docker.sh.conf
USERNAME="alice"
PASSWORD="s3cret"
REGISTRY="registry.example.com"
```

Environment variables and CLI arguments override config-file values.

## How It Works

1. A temporary directory is created and exported as `DOCKER_CONFIG`.
2. Credentials are resolved (config file → env vars → CLI args → interactive prompt).
3. `docker login` is executed using `--password-stdin`.
4. If login succeeds, the remaining arguments are executed as `docker <COMMANDS...>`.
5. On exit (success or failure), the temporary directory is removed via a `trap`.

Command output and exit status are captured in `CMD_OUTPUT` and `CMD_STATUS` for programmatic use in wrappers or CI scripts.

## Requirements

- Bash 4+
- Docker CLI

## License

MIT
