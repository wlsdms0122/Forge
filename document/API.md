# Forge API Reference

`forge` is an LLM-invocation daemon and its client, shipped as one binary. The
CLI is the surface for using forge: every consumer (a script, a service, a
workflow subprocess) runs the `forge` binary as a subprocess. Nothing else
opens the daemon's Unix socket directly.

```
forge serve                       run the daemon (long-running)
forge <subcommand> ...             client subcommands → JSON-RPC over the socket
```

This document covers the full CLI surface and the JSON-RPC methods underneath.
For what a workflow file holds and the verbs Forge lends a run, see
**[Spec.md](./Spec.md)**.

- [1. Invocation & configuration](#1-invocation--configuration): version, binary/socket discovery, config, env, global options, exit status
- [2. CLI surface](#2-cli-surface): [`serve`](#forge-serve) · [`workflow`](#forge-workflow) · [`schedule`](#forge-schedule) · [`job`](#forge-job) · [`resource`](#forge-resource) · [`service`](#forge-service) · [`status`](#forge-status) · [`policy`](#forge-policy) · [`token issue`](#forge-token-issue)
- [3. RPC transport](#3-rpc-transport)
- [4. RPC methods](#4-rpc-methods)
- [5. Authentication](#5-authentication)
- [6. Policy / ACL](#6-policy--acl)
- [7. Error types](#7-error-types)

---

## 1. Invocation & configuration

### Version

`forge --version` prints the product version, the `[package] version` of
`manifest.toml` (e.g. `0.1.0`), and exits. The same
version appears in `forge status` under the daemon's identity and in the
instance's `runtime.json`, so a client can tell which build a running daemon is.

### Binary discovery

| Source | Used by |
|--------|---------|
| `FORGE_BIN` env | consumers locating the binary; falls back to `forge` on `PATH` |
| `forge` on `PATH` | interactive use |

### Socket discovery

The socket is derived from the instance alone, not from config:

```
socket       = <instanceHome>/forged.sock
instanceHome = <XDG_CONFIG_HOME | ~/.config>/forge/<instance>
instance     = --instance  >  FORGE_INSTANCE  >  "default"
```

`serve` binds that canonical socket. A client falls back to it but honors
`FORGE_SOCKET` first, so a spawned child reaches the exact daemon that spawned it
without re-deriving the instance. A client never reads config.

An *instance* is one named daemon, with its own socket, config and state.
Several daemons running side by side are several instances.

### Config resolution (`serve` only)

The daemon reads one config file, and clients never read config. The file is
the `--config` path when one is given, and `<instanceHome>/config.toml`
otherwise. Each key then resolves in this order:

```
the file read  >  FORGE_* env vars  >  built-in defaults
```

An env var fills only a key the file leaves unset (or, for a `[pool]` key, sets
to a number that is not positive).
A `--config` path with no file behind it is a `ConfigError`
(`config <path>: no such file`); with no `--config`, `<instanceHome>/config.toml`
is read if it is there and the defaults apply if it is not.

### Config file (`config.toml`)

Every key is optional and has a built-in default, so a minimal toml declares
only what differs from the defaults and the managed services. A relative path
written in the toml resolves against the toml's directory; unspecified
directories and logs default under `instanceHome`. The state dir is
instance-owned (`<instanceHome>/state`) and not configurable, like the socket.

Every value the file writes is read or refused. A key outside the table below,
or a value of another type than its key takes, fails `serve` and
`service reload` with a `ConfigError` that names the table, e.g.
`config [directory]: unknown key 'root'; known keys: policy, working`. A
provider's keys besides `kind` are its settings, string values, and a setting
its kind does not read skips the provider as a missing one does.

| Table / key | Default | Meaning |
|---|---|---|
| `[directory]` `working` | `<instanceHome>/document` | the working directory: a relative workflow or file path (prompts, scripts) resolves under it, an absolute one is used as written. A relative value resolves against the toml's directory. |
| `[directory]` `policy` | `<instanceHome>/policy` | policy files; a relative value resolves against the toml's directory. |
| `[log]` `jsonl` / `error` | `<instanceHome>/log/forge.log.jsonl` · `…/error.log` | structured + stderr logs |
| `[log]` `maximum_bytes` | `52428800` (50 MiB) | single-file rotation threshold; ≤0 disables rotation |
| `[pool]` `maximum_concurrent_steps` | `4` | concurrent step cap (each `shell` run and each `agent` turn holds a slot); excess queues FIFO |
| `[pool]` `maximum_active_runs` | `256` | concurrent registered-run cap |
| `[provider.<name>]` `kind` (+ settings) | one `claude` (claude-cli) | backend instances. `kind` = `claude-cli` \| `codex-cli` \| `openai-compat`. CLI kinds accept `executable` (default: the CLI's name on `PATH`); `openai-compat` requires `endpoint`, the base URL, and an Agent reference without a model leaves the choice to the endpoint. A provider without a known `kind` or a required setting, or with a setting its kind does not read, is skipped with a warning on stderr. Declaring any drops the built-in claude default, so list it explicitly alongside others. API keys via `FORGE_PROVIDER_<NAME>_API_KEY` env only. |
| `[service.<name>]` `command` (+ `working_directory`/`environment`/`auto_spawn`/`log_file`/`restart_backoff_initial_milliseconds`/`restart_backoff_maximum_milliseconds`/`restart_crash_loop_limit`) | no service; for a declared one: `auto_spawn` `true`, `log_file` `<instanceHome>/state/services/<name>.log`, `restart_backoff_initial_milliseconds` `1000`, `restart_backoff_maximum_milliseconds` `30000`, `restart_crash_loop_limit` `5` | a managed child process forge spawns and supervises. `command` is its argv; a relative `command[0]` that contains `/` resolves against the toml's directory. A block without `command` is skipped with a warning on stderr. See CONFIG SCHEMA in `forge serve --help` |
| `[hooks]` `logging` | `true` | log each agent invocation (request, response, error) to the forge log |

The socket is not a config key; it lives at `<instanceHome>/forged.sock`
(see *Socket discovery*). Run `forge status` (or `--json`) to print the daemon's
effective config + every key's source (`toml`/`env`/`default`).

### Environment variables

| Var | Meaning |
|-----|---------|
| `FORGE_BIN` | path to the `forge` binary: set by the daemon for its shell, agent and service subprocesses, with the binary's directory put first on their `PATH`; read by consumers to find the binary |
| `FORGE_INSTANCE` | instance name when `--instance` is omitted; selects the daemon socket |
| `FORGE_SOCKET` | exact socket path; overrides instance. Injected into spawned subprocesses |
| `FORGE_STATE` | daemon state dir injected into subprocesses for `$FORGE_STATE/scratch/…` artifacts (not socket discovery) |
| `FORGE_ACCESS_TOKEN` | daemon-signed bearer token carried on every RPC: injected into workflow subprocesses at spawn, set by operators for direct use |
| `FORGE_BOOTSTRAP_FD` | read by `serve`: the fd it writes the boot-minted `system:admin` token to before closing it (section 5) |
| `FORGE_PROVIDER_<NAME>_API_KEY` | API key for `[provider.<name>]`, with `<NAME>` the provider's name in upper case |
| `FORGE_WORKING_DIRECTORY` / `FORGE_POLICY_DIRECTORY` | `serve`: `[directory]` `working` / `policy` where the file leaves it unset |
| `FORGE_LOG_JSONL` / `FORGE_ERROR_LOG` / `FORGE_LOG_MAXIMUM_BYTES` | `serve`: `[log]` `jsonl` / `error` / `maximum_bytes` where the file leaves it unset |
| `FORGE_POOL_MAXIMUM_CONCURRENT_STEPS` / `FORGE_POOL_MAXIMUM_ACTIVE_RUNS` | `serve`: `[pool]` `maximum_concurrent_steps` / `maximum_active_runs` where the file leaves it unset or not positive |

### Global options

Every client subcommand accepts these, placed **after** the leaf subcommand
(`forge workflow describe bot/review.yaml --instance prod`):

| Option | Meaning |
|--------|---------|
| `--instance <name>` | instance selecting the daemon socket (default `default`) |
| `--token <token>` | bearer token for the call; overrides `FORGE_ACCESS_TOKEN` |

(To reach a daemon at a non-default socket, set `FORGE_SOCKET`; children inherit it.)

Every RPC requires a token (except read-only `daemon.status`), `token.issue`
included. It is supplied as input (`--token` or the `FORGE_ACCESS_TOKEN` env
var) and never minted on the caller's behalf. The first token is the daemon's
boot-minted `system:admin`, handed to its launcher over an inherited fd; from
there issuance is delegation (section 5).

### Exit status

| Code | Meaning |
|------|---------|
| 0 | success |
| 1 | the command itself failed: `serve` could not boot (a config it cannot load included), `service register` could not register or lost the daemon, `policy check` denied, `workflow check` found a failing file |
| 4 | the request could not be formed: a missing token, a bad JSON option, conflicting flags, an unusable instance or socket path |
| 5 | the call failed: the daemon returned an RPC error or could not be reached, or `service describe` named a service that is not registered |
| 6 | RPC rejected for a stale or invalid token; reissue it |
| 64 | argument parse error (`EX_USAGE`) |

The exit code reports the call, not the work it started. A `workflow dispatch` whose run fails still exits 0 once the call went through; the failure is in the result (`"status":"failed"` and `error`). A `service send` the service answers with an error is the call's own answer, so it comes back as `ServiceFailed` and exits 5.

---

## 2. CLI surface

Output is human-friendly plain text by default; pass `--json` for
machine-parseable output. The "RPC" column links each command to section 4.

### `forge serve`

Run the LLM-invocation daemon over a Unix socket. Long-running; owns LLM
backends, workflow execution, schedules, and the ACL gate.

```
forge serve [--instance <name>] [--config <config>]
```

`--instance` picks where to bind (`<instanceHome>/forged.sock`); `--config` only
locates the daemon's settings/data. Under `<instanceHome>`: `forged.sock` (RPC socket) and
`runtime.json` (self-record: pid, instance, socket, resolved paths; written on
boot, deleted on clean shutdown). Refuses to start if a live daemon already holds
the socket. Signals `SIGINT`/`SIGTERM` → graceful shutdown.

### `forge workflow`

Dispatch and inspect workflow runs.

Hot reload applies content edits within the workflow schema understood by
the running daemon; it is not a schema-migration mechanism. A breaking workflow
key change must be deployed as one generation: stop every daemon reading those
workflows, install the matching binary and workflows, then restart. Forge intentionally
does not retain legacy decoder keys solely to bridge a mixed-generation process.

#### `forge workflow dispatch`

Dispatch a workflow run. RPC: `workflow.dispatch`.

```
forge workflow dispatch [<path>] [--spec <spec>] [--inputs <json>]
                        [--parameters <json>] [--correlator <str>]
                        [--origin <json>]
                        [--root-id <id>] [--parent-id <id>]
                        [--async] [--stream] [--json]
```

| Option | Meaning |
|--------|---------|
| `<path>` | the workflow's path (positional), absolute or under the working directory, e.g. `bot/review.yaml`. Omit when using `--spec` |
| `--spec` | inline workflow JSON, one procedure; use instead of the path argument. The run goes by `<inline>` and is gated by that sigil |
| `--inputs` | workflow inputs, JSON object (default `{}`) |
| `--parameters` | caller passthrough, JSON object; rides the log envelope only |
| `--correlator` | opaque string, ridden through to `service.message` frames |
| `--origin` | `{"kind":"...","id":"..."}`: what dispatched the run |
| `--root-id` / `--parent-id` | parent node-tree context to inherit (tree root id + parent node); normally omitted, since each run self-roots at its own run_id |
| `--async` | return as soon as dispatched (fire-and-forget) |
| `--stream` | stream the run's progress as JSONL (mutually exclusive with `--async`) |

Without `--async`, the command blocks until the workflow completes and
returns the full result. With `--async`, it returns immediately with
`{run_id, path, status:"running"}`; the run continues in the background
and is observable in the forge log.

With `--stream`, the command keeps the connection open and prints the run's
progress as JSONL, one object per line (RPC: `workflow.dispatch_stream`): first
the ack (`{id, result:{run_id, path, status:"streaming"}}`), then
`{"kind":"workflow.event", ...}` lines, then a terminal
`{"kind":"workflow.result","result":{...}}` with the result shape of a blocking
dispatch. Child workflows dispatched by the run share its root and stream
too. Disconnecting does not cancel the run (use `workflow cancel`).
`--stream` implies JSON output.

Events of runs this stream's root does not await carry `"unawaited": true`.
A run is unawaited when the path from the root to it crosses at least one
`--async` dispatch edge. The run above that edge does not wait for it, so once
the root finishes and the subscription closes, this stream relays no more
events from below the edge. A consumer must not wait forever on a `started` it
saw for such a run; it observes the run's completion by streaming that run
itself, or through `workflow.list_active`.

The flag holds in one direction only. Its presence means the terminal event may
never arrive on this stream. Its absence does not promise delivery: a cancelled
parent, a crash or a dropped connection can still cut a stream short, so a
consumer needs a closing rule of its own for those cases.

`unawaited` belongs to the pair of a stream and a run, not to the run: a stream
of the async run itself awaits it. An event carries `"async": true` when the
edge that started its run did not await that run; the flag is not inherited by
the run's children. The relay derives `unawaited` for each stream. It filters
no events by lineage: events of unawaited children are relayed like any other,
and the consumer decides what to display.

Identity and envelope: the bearer token carries the caller's identity. A
workflow subprocess's injected token is a `cli:<path>` token; root /
correlator / parameters / origin are then inherited from the parent run
server-side and the corresponding flags are ignored (a nested run cannot forge
its own coordinates). An operator token (`system:*`) carries no parent, so
those flags apply.

#### `forge workflow describe`

Show one workflow's calling contract: description, inputs (type and hint)
and the return type. Counterpart to `service describe`. RPC:
`workflow.describe`.

```
forge workflow describe <path> [--json]
```

#### `forge workflow active`

Show runs the pool is currently tracking (queued / running / cancelling).
RPC: `workflow.list_active`.

```
forge workflow active [--json]
```

#### `forge workflow health`

One-shot health check of the workflow pool: slots, waiter ages, run trees,
spawn rate, advisory flags. RPC: `workflow.health`.

```
forge workflow health [--json]
```

#### `forge workflow cancel`

Cancel a queued or running workflow. RPC: `workflow.cancel`.

```
forge workflow cancel <run-id> [--json]
```

#### `forge workflow check`

Check workflow YAML file(s) the way the daemon reads them. Local-only; does
not contact the daemon. Intended for CI and pre-commit hooks. **No RPC
counterpart.**

```
forge workflow check <path>...
```

Reads each file the way the daemon reads one: through the
YAML front end leaning on Forge's library, loaded, held to the file
convention (a public procedure `main`), and built against the library, the
natives and std. What the daemon refuses for a file is what the check prints, so a
file passes the check where the daemon admits it. Beside that, no plain
string may hold `${` (a string is a literal; `format` interpolates). A line
per file: `✓ <path>`; `✗ <path>: cannot read: <error>`; `✗ <path>: refused`
followed by the refusal on an indented line (a build refusal starts `build:`);
or `✗ <path>: N issue(s)` followed by indented issue lines. When any file
fails, `N file(s) failed` is written to stderr and the exit code is 1;
otherwise it is 0. Shell globs are expanded by the shell.

### `forge schedule`

Inspect, create, and toggle workflow schedules, both repeating and one-shot.

A schedule fires its workflow on a **trigger**, exactly one of:

| flag | format | meaning |
|------|--------|---------|
| `--every` | duration (`30s 5m 1h 2d`, compound `1h30m`) | repeat forever, every interval |
| `--at` | `HH:mm` (24h) + `--timezone` (IANA), optional `--days mon,wed,fri` | repeat on a wall-clock |
| `--once` | `"yyyy-MM-dd HH:mm:ss"` + `--timezone` | fire once at this wall-clock time |
| `--after` | duration (`30s 5m 1h 2d`, compound `1h30m`) | fire once, this much from now (timezone-agnostic) |

A duration is one or more `<int><unit>` tokens (`s`/`m`/`h`/`d`) summed:
`90m` and `1h30m` are both valid; a bare integer is seconds. `--after` is
resolved against the daemon clock at creation and stored as an absolute time,
so the caller never computes wall-clock time itself and a reload never slides
the fire time.

Repeating triggers (`--every`/`--at`) fire until the schedule is deleted.
One-shot triggers (`--once`/`--after`) fire exactly once, and the daemon removes a spent one
once it has fired, unless that fire was denied: a denied one-shot stays listed
until it is deleted. Fire-state lives in a daemon-owned ledger
(`state_directory/fire-ledger.json`), separate from the declaration:
recording it *before* dispatch gives at-most-once (no re-fire if the daemon
dies mid-fire).

Schedules are daemon state: one file each under `state_directory/schedule/`,
written by `create` and removed by `delete`, and a schedule's id is where its
file sits there, without the extension. `set_enabled` records in the
daemon-owned ledger (`state_directory/schedule-enabled.json`); a schedule is
enabled while the ledger holds its id against the workflow it fires.

| Command | RPC | Notes |
|---------|-----|-------|
| `forge schedule list [--json]` | `schedule.list` | all schedules (repeating + one-shot) |
| `forge schedule create (--workflow <w> \| --spec <json>) (--every <dur> \| --at <HH:mm> --timezone <tz> [--days …] \| --once <wall-clock> --timezone <tz> \| --after <dur>) [--id --inputs --concurrency]` | `schedule.create` | exactly one trigger flag |
| `forge schedule delete <id> [--json]` | `schedule.delete` | any schedule |
| `forge schedule enable <id> [--json]` | `schedule.set_enabled` | `enabled=true` |
| `forge schedule disable <id> [--json]` | `schedule.set_enabled` | `enabled=false` |

### `forge job`

Create and track work tickets (jobs) agents coordinate through. A job is a
*work ticket*: durable shared data that carries a task's context across
ephemeral agent sessions, distinct from a workflow (the action) and a run
(one execution). A ticket is a free-form canvas, not bound to any workflow.
Its association with a run is observed: when a run's session runs a
ticket-targeting command (`job show` / `job update`), the daemon records the
attachment. `status` is a free string forge never interprets; its vocabulary
belongs to the agents. Every mutation is stamped with the id of the caller's
token (each token has its own id), not with its principal.

| Command | RPC | Notes |
|---------|-----|-------|
| `forge job create --title <t> [--brief --refs --origin --plan --parent-job --status --id] [--json]` | `job.create` | `--refs`/`--plan` take JSON arrays; `--origin` an opaque JSON object |
| `forge job show <id> [--json]` | `job.show` | full ticket: brief, refs, plan, comments, events, children |
| `forge job list [--status <s>] [--origin-key <k> --origin-value <v>] [--json]` | `job.list` | summary rows, newest-updated first |
| `forge job update <id> [--note --brief --ref --ref-note --item --item-desc --item-status --status] [--json]` | `job.update` | field-level ops, append-safe |
| `forge job delete <id> [--json]` | `job.delete` | remove a reviewed ticket (unlinks it from its parent) |

### `forge resource`

Inspect files under the working directory. The daemon hands out only relative
paths with no hidden part and no link leading out of the directory, and external tools (admin, scripts, agents) read files through these RPCs
instead of touching the filesystem.

#### `forge resource list`

List files under the working directory. RPC: `resource.list`.

```
forge resource list [--json]
```

Plain output: tab-separated `<path>\t<size>\t<mtime-iso>`.
JSON: `{ "resources": [ { "path": "...", "size": N, "mtime": "..." } ] }`.

#### `forge resource read`

Read a single resource file. RPC: `resource.read`.

```
forge resource read <path> [--max-bytes N] [--json]
```

| Option | Meaning |
|--------|---------|
| `<path>` | Path relative to the working directory. An absolute path, a `..` part, a hidden part and a link leading out are rejected by the daemon |
| `--max-bytes` | Truncation cap, default 64 KiB. Bytes beyond are dropped (a `... (truncated)` marker is appended) and `truncated=true` |

Plain output: body. JSON: `{ "path", "body", "size", "truncated" }`.

### `forge service`

Inspect, register, and call external services, and control the managed
child processes the daemon supervises. An external service (e.g. `slack`) is a
process that registers with the daemon and implements a capability forge
itself does not.

#### `forge service list`

List registered services. RPC: `service.list`.

```
forge service list [--json]
```

#### `forge service describe`

Show one service's call schema: its description and the actions/ops it
accepts, with params and returns. The contract to consult before `forge
service send`. RPC: `service.list` (filtered to one).

```
forge service describe <name> [--json]
```

#### `forge service register`

Run the current process as a service, a long-lived **co-process**.
forge owns the socket and the `service.register` handshake; the parent
process speaks JSON over stdio and never touches the socket. RPC:
`service.register` + `service.ack`.

```
forge service register <name> [--schema <json>]
```

| Option | Meaning |
|--------|---------|
| `<name>` | service name to register (e.g. `slack`) |
| `--schema` | call schema, JSON object (advertised via `forge service list`) |

The bearer token (`FORGE_ACCESS_TOKEN` / `--token`) is read once at startup.
The daemon binds the service name to the token's principal: a `service:<name>`
token may only register/ack as that service (a mismatching `<name>` fails
loud), a `cli:*` workflow subprocess is rejected outright, and operator
principals (`system:*`, `admin:*`) may register any name.

| Stream | Content |
|--------|---------|
| stdout | one JSON line per incoming `service.message` frame |
| stdin | one JSON line per ack: `{"message_id":"...","result":{...}}` or `{"message_id":"...","error":{...}}` |

It connects and registers once. Any failure (connect refused, register
rejected, connection lost) exits **1**; the parent treats that as fatal and
exits, and the supervisor respawns the whole service with a fresh token.
Exits 0 on stdin EOF.

#### `forge service send`

Hand a JSON payload to a registered service. RPC: `service.send`. To run a
workflow use `forge workflow dispatch`: `send` is for external services only.

```
forge service send <name> --payload <json> [--async] [--json]
```

`--async` returns as soon as the work is dispatched (`{message_id,
status:"dispatched"}`) instead of blocking for the service's result.

#### Managed-service control

Control the child processes forge itself spawns/supervises (`[service.<name>]`
entries in `config.toml`). `run`, `shutdown`, `restart` and `reload` are the
operator surface: a `cli:*` workflow-subprocess token is rejected, and a
`service:<name>` token may only act on its own name and may not use `reload`
(global control). `status` takes any token.

| Command | RPC | Notes |
|---------|-----|-------|
| `forge service run <name> [--json]` | `service.run` | start a managed service |
| `forge service shutdown <name> [--json]` | `service.shutdown` | stop a managed service |
| `forge service restart <name> [--json]` | `service.restart` | stop and start |
| `forge service status [--json]` | `service.status` | supervision state of every managed service |
| `forge service reload [--json]` | `service.reload` | re-read `config.toml`'s `[service.*]` tables and apply the diff |

### `forge status`

Print the daemon's identity (instance, version, socket, pid, uptime), its effective
`ForgeConfig` with each value's source (toml / env / default), and runtime counts
(schedules, jobs, services). RPC: `daemon.status` (token-free). If the
socket is dead, falls back to reading `runtime.json` for a "not running / crashed"
diagnostic.

```
forge status [--json]
```

### `forge policy`

Inspect the ACL policy that gates `workflow dispatch`.

| Command | RPC |
|---------|-----|
| `forge policy list [--json]` | `policy.list` |
| `forge policy check <principal> <workflow> [--json]` | `policy.check` |

`policy check` exits 1 (in addition to printing) when the call is denied.

### `forge token issue`

Mint a daemon-signed bearer token. RPC: `token.issue`. Like every RPC it
requires a presented token, and mints under attenuation: only an admin-tier
presenter (`system:admin` / `admin:<user>`) may delegate (section 5).

```
forge token issue <principal> [--json]
```

`<principal>` is required: `system:runner`, `system:admin`, or `admin:<user>`.
The issuer states the identity explicitly. See section 5 for the
issue gate. The very first token comes from the daemon's boot fd, not this call.

---

## 3. RPC transport

Clients speak **line-delimited JSON-RPC over a Unix domain socket**
(`<instanceHome>/forged.sock`). One JSON object per line, `\n`-terminated.

Request:

```json
{"id": "<client-id>", "method": "<method>", "params": { ... }}
```

Response on success:

```json
{"id": "<client-id>", "result": { ... }}
```

Response on error:

```json
{"id": "<client-id>", "error": {"type": "<ErrorType>", "message": "<text>"}}
```

**Streaming methods** (`service.register`, `workflow.dispatch_stream`)
keep the connection open and emit multiple lines: first an ack envelope, then a
stream of frames.

The CLI flattens this: a `--json` command prints the `result` object; an RPC
error becomes a non-zero exit (code 5, or 6 for `TokenRejected`) with the
message on stderr.

---

## 4. RPC methods

Auth column: `token` means a valid bearer token is required in
`params.token`; `operator` means a valid token whose principal is not `cli:*`
(a `cli:*` token is refused with `ProtocolError`); `none` means
unauthenticated (read-only). All methods require a token except
`daemon.status` (read-only introspection and liveness). `token.issue` mints
under attenuation from the presenter's principal (section 5).

| Method | Auth | Streaming | CLI |
|--------|------|-----------|-----|
| `workflow.dispatch` | token | no | `workflow dispatch` |
| `workflow.dispatch_stream` | token | **yes** | `workflow dispatch --stream` |
| `workflow.describe` | token | no | `workflow describe` |
| `workflow.list_active` | token | no | `workflow active` |
| `workflow.health` | token | no | `workflow health` |
| `workflow.cancel` | token | no | `workflow cancel` |
| `schedule.list` | token | no | `schedule list` |
| `schedule.set_enabled` | token | no | `schedule enable`/`disable` |
| `schedule.create` | token | no | `schedule create` |
| `schedule.delete` | token | no | `schedule delete` |
| `job.create` | token | no | `job create` |
| `job.show` | token | no | `job show` |
| `job.list` | token | no | `job list` |
| `job.update` | token | no | `job update` |
| `job.delete` | token | no | `job delete` |
| `resource.list` | token | no | `resource list` |
| `resource.read` | token | no | `resource read` |
| `policy.list` | token | no | `policy list` |
| `policy.check` | token | no | `policy check` |
| `token.issue` | token | no | `token issue` |
| `daemon.status` | none | no | `status` |
| `service.send` | token | no | `service send` |
| `service.list` | token | no | `service list` / `service describe` |
| `service.register` | operator | **yes** | `service register` |
| `service.ack` | operator | no | (internal to `service register`) |
| `service.run` | operator | no | `service run` |
| `service.shutdown` | operator | no | `service shutdown` |
| `service.restart` | operator | no | `service restart` |
| `service.status` | token | no | `service status` |
| `service.reload` | operator | no | `service reload` |

### `workflow.dispatch`

Single entry point for all workflow dispatch. Operator/runner/admin fresh-root
calls and nested calls from inside a workflow are distinguished by the **token**.

**params**

| Field | Req | Notes |
|-------|-----|-------|
| `token` | ✅ | identity derived from claims; caller cannot set `principal` |
| `path` | △ | the workflow's path, absolute or under the working directory, exclusive with `spec` |
| `spec` | △ | inline workflow JSON, one procedure; the run goes by `<inline>` in place of a path |
| `inputs` | no | object, default `{}` |
| `async` | no | bool, default `false` |
| `parameters` / `correlator` / `origin` / `root` | no | honored only for fresh-root tokens; for a workflow-subprocess token they are inherited from the parent `WorkRecord` and caller values are ignored |

`root`: `{"root_id": "...", "parent_id": "..."}`, the parent node tree to attach under. Omit to self-root (the run's node tree roots at its own run_id, so `root_id == run_id`).
`origin`: `{"kind": "...", "id": "..."}`, what dispatched this run. The kind is the caller's `origin` where it gives one, and `rpc` where it gives none; a schedule fire has kind `schedule` and the schedule id, a dispatch sent from a run's subprocess has kind `workflow` and the parent run id, and a run started by a `dispatch` step has kind `manual` and no id. Read inside the workflow through the `origin` verb, `{ call: { procedure: origin } }`, whose `kind` and `id` are these.

**result** for `async=false`:

```json
{"run_id":"...","path":"...","status":"ok","duration_ms":1234,"output":<value>}
{"run_id":"...","path":"...","status":"failed","duration_ms":1234,"error":{"type":"...","message":"..."}}
```

`output` is the value the workflow returned, as itself: a struct as an
object of its fields, a dictionary as an object of its entries with each key
spelled as text, an array as an array, a string, a number or a bool as
itself, and null as null. Bytes are an array of their numbers. A value JSON
cannot hold, a procedure or a dictionary two of whose keys are spelled as
one text, fails the run with `UnwritableValue`. A run that failed returned
nothing and has no `output`: its `status` and `error` say why. A
`workflow.completed` event carries the same value in its `output` field.

**result** for `async=true`:

```json
{"run_id":"...","path":"...","status":"running"}
```

`running` acknowledges acceptance, not completion. The policy gate is
evaluated before the call returns: a denied principal gets the error
synchronously, never a `running`. A background failure after acceptance is
recorded as a `dispatch.failed` event (error level) in the forge log.

### `workflow.dispatch_stream`

Streaming variant of `workflow.dispatch`, with the same params (minus `async`)
and the same identity/envelope/policy rules. The connection stays open for the run's
lifetime and relays its progress:

```json
{"id":"<client-id>","result":{"run_id":"...","path":"...","status":"streaming"}}
{"kind":"workflow.event","event":"workflow.started","run_id":"...","workflow_name":"...","inputs":{...},"input_preview":"...","input_len":...,"root_id":"...","ts":..., ...}
{"kind":"workflow.event","event":"step.started","step":"...","action":"Forge.shell|Forge.agent|...","node_id":"...","parent_node_id":"...", ...}
{"kind":"workflow.event","event":"step.completed","step":"...","output":<value>,"output_preview":"...","output_len":..., ...}
{"kind":"workflow.event","event":"workflow.completed","output":<value>,"output_preview":"...","output_len":...,"duration_ms":..., ...}
{"kind":"workflow.result","result":{...same shape as blocking dispatch result...}}
```

An event's `workflow_name`, like a run record's, is the workflow's path, or
`<inline>`. Event lines are `WorkflowEvent` objects (`workflow.started/completed/failed`,
`step.started/completed/failed`) filtered to this run's **root**. A
step is a call of a verb that reaches outside the program, from its
native's start to its return or throw, named by the statement that called
the verb, and its `action` is the verb's full name, or the native's
(`Forge.Native.<verb>`) where a workflow calls one directly. A
`step.completed` event's `output` is the value the verb returned, in the
JSON form a run's `output` takes, and is left out where JSON cannot hold
it. `step.completed` and `workflow.completed` carry `output_preview` and
`output_len` beside `output`, and `workflow.started` carries
`input_preview` and `input_len` beside `inputs`: the preview is the
value's JSON text, or a string's own text, cut to its first 2000
characters, and the length counts the characters of the whole text. A
null previews as `null`. Where a value is left out, its preview and
length are left out with it, so a `step.completed` without
`output_preview` is a step whose value JSON cannot hold. The forge log
writes the previews and leaves out `output` and `inputs`. A
`step.failed` event's `error_message` is the trace of the call, a
colon, and the failure's sentence, whatever the failure and whether or not
a catch takes it, and a refusal that carries a trace of its own keeps that
deeper trace, so the rounds of a loop and the pieces of a fan-out, which
share one `step`, differ there. Child workflows
dispatched by the run (a `dispatch` step) inherit the root and stream
too; `root_id`/`node_id`/`parent_node_id` let the consumer rebuild the
tree. A policy denial is returned as a plain RPC error line (no stream). If
the run fails to even start after the ack (e.g. run cap), the terminal
`workflow.result` line carries the real error type in `error.type`, by the same
mapping the blocking path's RPC error envelope uses. If the client disconnects
mid-run the run continues (same semantics as `async=true`); interruption is
`workflow.cancel`'s job.

### `workflow.describe`

**params** `{"token","path"}`. **result**

```json
{"path","description"?,
 "inputs":{"<key>":{"type","hint"?}},
 "returns"}
```

`inputs` is `main`'s parameters. `type` is the declared type
as the language spells it (`String`, `Array<String>`, `String?`, …); an input
of an Optional type is one a caller may leave out, and the daemon hands it
null. An input the file gives a `default:` reads Optional too, and the
workflow settles the null it is handed to that default. `hint` is what the file writes under the input's `hint:`. `returns` is the declared return type. Empty `inputs` is returned as
`{}` (not omitted) so the caller can iterate without null-checks. Unknown
workflow → WorkflowNotFound `workflow not found: <path>`.

### `workflow.list_active`

**params** `{"token"}`. **result**

```json
{"runs":[{"run_id","workflow_name","origin","principal","state",
          "enqueued_at","started_at","held_slots"}],
 "maximum_concurrent_steps":N,"free_slots":N,"queued_waiters":N}
```

`state` ∈ `queued|running|cancelling`. Times are epoch seconds. `started_at`
is omitted while queued.

### `workflow.health`

One-shot pool health snapshot with advisory flags.

**params** `{"token"}`. **result**

```json
{"slots":{"max":N,"free":N,"waiters":[{"run_id","waited_ms"}]},
 "runs":{"active":N,"cap":N,"refused_total":N,
         "oldest":[{"run_id","workflow_name","state","age_ms"}],
         "trees":[{"root_id","runs":N,"names":{"<path>":N}}]},
 "dispatch":{"last_60s":N},
 "flags":[{"kind":"...","class":"saturation|anomaly", ...}]}
```

`flags` are threshold-derived advisories: `long_wait` (a waiter queued ≥60s),
`long_run` (a run alive ≥30min), `big_tree` (≥16 runs under one root),
`high_rate` (≥30 dispatches in 60s), `runs_refused` (any refusal in 60s).
Each flag carries the fields of the row that tripped it.

### `workflow.cancel`

**params** `{"token","run_id"}`. **result** `{"cancelled":bool,"run_id"}`.
`cancelled=false` means the id was already unregistered (finished/failed).
Cancelling a live run is gated by policy on that run's workflow path, the
same dispatch ACL, so a principal that may not dispatch a workflow may not
cancel its runs either.

### `schedule.list`

**params** `{"token"}`. **result**

```json
{"schedules":[{"id","workflow","trigger","concurrency","enabled",
               "inputs","source","next_fire_at"?,
               "last_attempt_at"?,"last_outcome"?,"outcome_at"?,"reason"?,"spent"?}],
 "failures":[...],"flags":[{"kind":"schedule_denied","schedule_id","reason"?,"outcome_at"?}]}
```

`trigger` is the trigger dict, one of `{"every":"1h"}`,
`{"at":"09:20","days":["mon",…]?,"timezone":"Asia/Seoul"}`, or
`{"once":"2026-06-20 09:00:00","timezone":"Asia/Seoul"}`. All schedules appear
(repeating and one-shot). `next_fire_at` is a UTC ISO8601 display estimate
(absent for a spent one-shot). `last_attempt_at` is the last consumed fire
slot, from the ledger. It is an attempt, recorded before dispatch for
at-most-once, so it advances even when the fire could not launch.
`last_outcome` is that slot's disposition: `launched` (the scheduler committed
the slot to the run chain; the run's start is the `schedule.fired` log event
with its run_id, and its success or failure is in the run's own record; a
dispatch that refuses the run when it is admitted, at the run cap or during
shutdown, logs `schedule.denied` with `stage: dispatch` and that run_id),
`denied` (the fire could not start a run, with a machine-readable `reason`:
`workflow_missing`, `workflow_invalid` or `spec_decode` when its target could
not be resolved, `policy_denied` when the policy refuses its principal), or
`skipped` (the concurrency policy dropped it, a normal disposition and not a
failure). `last_outcome: "unknown"` means the disposition cannot be known (a
ledger entry from before an upgrade, or a crash between attempt and close); it
is reported as a value so it stays distinct from a clean close. The field is
absent only while an attempt is in flight. `last_attempt_at` is the wall-clock
moment of the attempt (the phase anchor slot is internal, and after downtime
catch-up the two differ). `spent` (one-shot only) is true when its slot was
consumed and it will not fire again. An attempt consumes the slot even if it
was denied, and a denied one-shot is not removed: it stays listed with its
flag until it is deleted. `flags` follows the `workflow.health` advisory
conventions: `schedule_denied` marks a schedule while its latest slot's
outcome is `denied`. `failures` lists the schedule files left out, each with
its refusal, a part of a directory the scan could not see among them at path
`<scan>`.

### `schedule.set_enabled`

**params** `{"token","id","enabled":bool}`. **result** `{"id","enabled"}`.
Gated by the dispatch ACL on the schedule's target workflow.

### `schedule.create`

Creates a schedule in `state_directory/schedule` (daemon-owned). Fails if the `id`
collides, no workflow loads at the `workflow` path, the inline `spec` fails
decode/validation, or the caller's principal is not allowed to dispatch the
target workflow (`policy/*.yaml`, checked against its path, or
`<inline>` for a spec). The caller's principal is not stored. Each fire runs as
`system:schedule:<id>` and is checked against the policy again, so the policy
must grant that principal the target (for example through `system:*` or
`system:schedule:*`). A fire the policy refuses starts no run, closes its slot
as `denied` with reason `policy_denied`, and is logged as a `schedule.denied`
event with `stage: resolve`.

Fire target via `workflow` (a path) or `spec` (inline), the same
rules as `workflow.dispatch`: mutually exclusive, and `spec` runs under the
`<inline>` sigil. A schedule file writes one of the two; a file writing both
is a load failure. At create time the spec is
read the way a workflow file is, through the YAML front end leaning on
Forge's library, and loaded, so what the front
end or the load refuses surfaces at create time. It is not built there: a
refusal of the build surfaces when the schedule fires. The spec is stored on
the schedule record as written and read again on every fire.

**params**

| Field | Req | Notes |
|-------|-----|-------|
| `token` | ✅ | any authenticated token |
| `workflow` | △ | the workflow's path, absolute or under the working directory, exclusive with `spec` |
| `spec` | △ | inline workflow JSON, one procedure; runs as `<inline>` |
| `every` | △ | interval duration (`"30s" "5m" "1h" "2d"`), repeating |
| `at` | △ | wall-clock `"HH:mm"` (24h), repeating; requires `timezone` |
| `once` | △ | wall-clock `"yyyy-MM-dd HH:mm:ss"`, one-shot; requires `timezone` |
| `after` | △ | relative duration, one-shot; resolved at creation, stored as absolute |
| `timezone` | △ | IANA id (`"Asia/Seoul"`), required with `at`/`once`; refused with `every`/`after` (`after` displays in UTC) |
| `days` | no | weekday filter for `at` (`["mon",…]`, any case); omit for every day; refused with `every`/`once`/`after` |
| `id` | no | string; auto-generated (`s-<ts>-<rand>`) if omitted |
| `concurrency` | no | `queue` \| `skip` \| `replace`, default `queue` |
| `inputs` | no | object passed to the workflow on fire |

Exactly one of `every` / `at` / `once` / `after`. **result**
`{"id","workflow","trigger","fire_at"?}` (`fire_at` present for
one-shot; `workflow` is the sigil `<inline>` when created with `spec`).

### `schedule.delete`

Deletes a schedule by id. Gated by the dispatch ACL on the schedule's target
workflow.

**params** `{"token","id"}`. **result** `{"id","deleted":true}`.

### `job.create`

Create a work ticket.

**params**

| Field | Req | Notes |
|-------|-----|-------|
| `token` | ✅ | any authenticated token |
| `title` | ✅ | human-readable title |
| `brief` | no | self-contained brief (default `""`) |
| `refs` | no | array of `{"ref","note"?}` objects or plain strings |
| `origin` | no | opaque JSON object (forge-agnostic; e.g. slack `{channel, thread_ts}`) |
| `plan` | no | array of `{"id"?:int,"desc","status"?}` objects or plain strings; omit `id` to auto-number |
| `parent_job` | no | parent ticket id; must exist, and the child is linked into its `children` |
| `status` | no | free string; a ticket created without one has none. forge sets no status of its own, on the ticket or on a plan item |
| `id` | no | string; auto-generated (`j-<rand>`) if omitted |

**result** `{"job_id","id","title","status"?}`.

### `job.show`

**params** `{"token","id"}`. **result** `{"job":{...}}`: the full ticket
(title, status, brief, refs, plan, comments, events, children, created/updated
stamps) plus derived `open` (an opening event with no terminal yet) and, when
the ticket has children, `children_detail` (`[{"id","title","status"?}]`, or
`{"id","missing":true}` for a dangling link). When called by a live run's
token, the daemon records the attachment as a touch event. Unknown id →
ProtocolError `job not found: <id>`.

### `job.list`

**params** `{"token","status"?,"origin_key"?,"origin_value"?}`; `status`
filters on the exact status string; `origin_key`+`origin_value` filter on an
origin-object entry. **result**

```json
{"jobs":[{"id","title","status"?,"updated_at","open",
          "last_event"?,"parent_job"?,"children"?,"origin"?}]}
```

Sorted by `updated_at`, newest first.

A job file that does not load is left out of the list and named once on the
daemon's stderr, at the reload that first meets it.

### `job.update`

Field-level edits: each present param applies independently (append-safe;
several runs may update one ticket concurrently).

**params** `{"token","id"}` plus any of: `note` (append a comment), `brief`
(set/replace), `ref` + `ref_note`? (append a reference pointer), `item` (int
plan-item id) + `item_status`? + `item_desc`? (an existing item keeps what is not given), `status`
(set the overall status). When called by a live run's token, the daemon
records the attachment as a touch event.

**result** `{"id","status"?}`.

### `job.delete`

**params** `{"token","id"}`. **result** `{"id","deleted":true}`. Removes the
ticket and unlinks it from its parent's children.

### `resource.list`

**params** `{"token"}`. **result** `{"resources":[{"path","size","mtime"}]}`.

`path` is relative to the working directory; `mtime` is ISO8601. Sorted by path.

### `resource.read`

Read one file under the working directory. An absolute path, a `..` part, a
hidden part and a link leading out are rejected by the daemon; oversize bodies are truncated and `truncated=true`.

**params**

| Field | Req | Notes |
|-------|-----|-------|
| `token` | ✅ | any authenticated token |
| `path` | ✅ | relative to the working directory |
| `maximum_bytes` | no | truncation cap; default 64 KiB |

**result** `{"path","body","size","truncated"}`. `size` is the full
(untruncated) byte count; a truncated `body` ends with a `... (truncated)`
marker line.

### `policy.list`

**params** `{"token"}`. **result**
`{"policy":{"<principal-pattern>":["<workflow-pattern>"]},"failures":[{"path","reason","mtime"}]}`.
`failures` lists policy files that couldn't be loaded (same convention as
`schedule.list`).

### `policy.check`

**params** `{"token","principal","workflow"}`. **result**
`{"principal","workflow","allowed":bool}`.

### `token.issue`

**params** `{"token","principal"}`. **result** `{"token","principal"}`.

Requires a presented token and mints under attenuation: only `system:admin` /
`admin:*` presenters may delegate (section 5). Issuable principals: `system:runner`,
`system:admin`, `admin:*`.

### `service.send`

Send a payload to a registered external service.

**params** `{"token","service","payload","async":bool?}`.

**result**: `async=false` gives the service's ack result (service-defined).
`async=true`: `{"service","message_id","status":"dispatched"}`.

### `service.list`

**params** `{"token"}`. **result** `{"services":[{"service","schema"?}]}`:
registered external services only, sorted by name; `schema` is present only
when the service advertised one.

### `service.register` (streaming)

Register an external service on a long-lived connection.

**params** `{"token","service","schema":object?}`. The service name is bound
to the verified principal: a `service:<name>` token may only register as that
service (mismatch fails loud), `cli:*` is rejected (a workflow subprocess
cannot register a service), operator principals may register any name.

**flow**

```
client → daemon : {"method":"service.register","params":{...}}
daemon → client : {"id":<req.id>,"result":{"registered":true,"service":"..."}}   ← ack
daemon → client : {"kind":"service.message","service","message_id",
                   "envelope":{...},"payload":{...}}                            ← repeats
client → daemon : {"method":"service.ack","params":{...}}                       ← same connection
```

The `envelope` carries forge's server-side coordinates:
`{run_id, origin, root_id?, id?, correlator?}`. The `payload` is
caller-sent and opaque to forge. Closing the connection unregisters the service.

### `service.ack`

Acknowledge a processed `service.message`.

**params** `{"token","service","message_id","result":object?}`, or `"error"`
instead of `"result"`. **result** `{"ok":true}`. Same principal↔service
binding as register: a `service:<name>` token cannot deliver results for
another service.

### `service.run` / `service.shutdown` / `service.restart`

Start / stop / restart a managed service (a `[service.<name>]` entry in
`config.toml`). Operator methods: a `cli:*` token is rejected; a
`service:<name>` token may only act on its own name.

**params** `{"token","name"}`. **result** is the service's status record:
`{"name","state","auto_spawn","crashes","pid"?,"started_at"?,"last_exit_code"?}`.

### `service.status`

**params** `{"token"}` (any authenticated token). **result**
`{"services":[{...status record...,"registered":bool}]}`, one row per
managed service; `registered` is whether a live service of that name is
currently registered on the service bus.

### `service.reload`

Re-read the daemon's `config.toml`, apply the `[service.*]` diff (removed
services are stopped, added `auto_spawn` ones started), and refresh the
config snapshot. Global service control: rejected for both `cli:*` and
`service:*` tokens.

**params** `{"token"}`. **result**
`{"reloaded":true,"added":[...],"removed":[...],"changed":[...]}`.

---

## 5. Authentication

Every RPC carries a bearer token in `params.token`. The token *is* the
request's identity: forge verifies its signature and reads `principal` from
its claims; it never inspects who the OS-level caller is. A request without a
valid token is rejected. forge does not mint a token on the caller's behalf:
the token is supplied as input (`--token` / `FORGE_ACCESS_TOKEN`), obtained
beforehand from `token.issue` (which itself requires a token) or, for the very
first token, from the daemon's boot fd handed to its launcher.

### Token model

The daemon signs tokens with a random seed minted at boot and held only in
memory: `base64(claims).base64(HMAC-SHA256(claims, seed))`. Claims carry the
`principal` and, for workflow-subprocess tokens, a `run_id`.

- Unforgeable: only forge knows the seed.
- Revocation by restart: a daemon restart rotates the seed, invalidating
  every outstanding token. A rejected token surfaces as `TokenRejected` (CLI
  exit 6); the holder re-issues and retries.

### Carrying the token

- **Workflow subprocess**: the daemon mints a `cli:<path>` token at spawn
  and injects it as `FORGE_ACCESS_TOKEN`. Never issuable over RPC.
- **admin**: the daemon's launcher; receives the boot-minted `system:admin`
  token over an inherited fd (`FORGE_BOOTSTRAP_FD`) and delegates from it.
- **runner / managed services**: receive an injected `FORGE_ACCESS_TOKEN` from
  their launcher (admin issues `system:runner` for the runner; the supervisor
  injects `service:<name>` for managed services). They do not self-issue. On
  `TokenRejected` (forge restart) the launcher re-mints and respawns them.

### Issuing tokens (`token.issue`)

`token.issue` is a normal authenticated RPC: it requires a presented token and
mints under attenuation, and **both** of these must hold:

1. the requested principal is in the issuable set (`isIssuable`), and
2. the presenter's principal may delegate it (`canIssue`); only `system:admin`
   and `admin:<user>` qualify.

A workflow subprocess only ever holds a `cli:*` token (re-minted fresh at every
process boundary), and `cli:*` may delegate nothing — so an LLM cannot escalate,
regardless of how it reaches the socket. There is no peer-credential gate; the
unforgeable token *is* the identity.

The bootstrap exception is the boot mint, not this RPC: at startup the daemon
mints one `system:admin` token, writes it to the fd named by
`FORGE_BOOTSTRAP_FD` (its launcher's pipe) and closes the fd. The token is not
written to disk or to a child's environment, so whoever launches the daemon
holds the first token. With no such fd and an interactive tty, the daemon
prints the token to stdout; otherwise it withholds the token.

Issuable principals: `system:runner`, `system:admin`, `admin:*`, each stated
explicitly by the issuer (no default). `cli:<path>` tokens are minted
internally at workflow-subprocess spawn, never over RPC.

### Principal classes

| Principal | Origin |
|-----------|--------|
| `cli:<path>` | workflow subprocess (daemon mints at spawn) |
| `service:<name>` | managed service subprocess (supervisor mints at spawn; never issuable over RPC). Bound to its own name on named service surfaces (service.register/ack/run/shutdown/restart) and rejected on global service control (service.reload) |
| `system:runner` | a runner process that dispatches workflows; issued over `token.issue` by an admin |
| `system:admin` | admin route (manual triggers); the daemon's boot token |
| `system:schedule:<id>` | the daemon's internal scheduler (repeating + one-shot fires) |
| `admin:<user>` | a named admin, issued over `token.issue`; may delegate like `system:admin` |

---

## 6. Policy / ACL

Every dispatch is gated by the policy store: a `workflow.dispatch` from an
operator, a runner or an admin, a schedule's fire, and a `dispatch` step inside
a workflow.

- YAML files (`*.yaml`) under the policy dir (`[directory] policy`, default
  `<instanceHome>/policy`). Each file is a flat mapping of **principal
  patterns** to lists of **workflow-path patterns**.
- Multiple files are union-merged by principal key. Changes hot-reload on the
  next dispatch, without a daemon restart.
- No rules (empty or missing policy dir) → closed-by-default → **every**
  `workflow.dispatch` denied.

**Pattern matching**

| Pattern | Matches |
|---------|---------|
| `cli:bot/response.yaml` | exact |
| `cli:*` | class wildcard |
| `*` | global wildcard |

Workflow-path patterns support exact, a trailing `*` (`bot/*` is every workflow under `bot/`), and `*`.

Inline specs (`workflow.dispatch` with `spec`) are anonymous: the caller
cannot choose a path, so they are gated under the fixed sigil `<inline>`.

```yaml
"system:*":     ["*"]
"cli:bot/response.yaml": ["automation/bank-jira-sync.yaml", "<inline>"]
```

Inspect with `forge policy list` / `forge policy check`.

---

## 7. Error types

The error envelope is `{"type": "<ErrorType>", "message": "<text>"}` and the fields a type carries beside them. A failed run's `error`, in a `workflow.dispatch` result and in a stream's `workflow.result`, is the same object, and a `workflow.event` names a failure by the same type. A run or a step that fails with a failure of the language (such as `aborted`, `cast_refused`, `concurrent_failed`) is typed by the name the language gives it, the name a workflow's `catch` reads. A `shell`, `invoke` or `dispatch` that runs past its `timeout` fails with Forge's deadline failure, typed `timeout` and read by a `catch` under that name; its envelope holds the type and the message only. A Forge failure that a workflow's `catch` may take keeps its Forge type on the wire; its row names the type the `catch` reads. Any other failure that is none of the types below is `InternalError` with its text. A failure that a run can meet as well keeps its type when a request meets it: `resource.read` answers `ResourceError` as a `resource` step does, and `workflow.dispatch` answers `WorkflowNotFound` as a `dispatch` step does. A request whose payload is malformed, or whose id is invalid, taken or missing in a store only requests reach, is refused with `ProtocolError`.

| Type | Meaning |
|------|---------|
| `ConfigError` | the `--config` file is not there, or `config.toml` is not TOML, has a key the loader does not read, or a value of another type than its key takes (`service.reload`; `serve` exits with it). Fix the file; a retry meets the same refusal |
| `BackendTimeout` | a backend call exceeded its timeout; a retry candidate |
| `BackendNonzeroExit` | a backend exited non-zero (also carries `exit_code`, `stderr`, `stdout`); a `catch` reads it as `nonzero_exit` |
| `BackendUnavailable` | a backend could not be reached (e.g. an OpenAI-compatible endpoint refused or errored) |
| `MalformedOutput` | a backend response was not the promised shape |
| `BackendProtocolViolation` | a CLI backend's successful turn broke its stream: malformed frames, no terminal result, or neither text nor a tool call |
| `IncompleteCompletion` | an agent turn ended without completing (a `finish_reason` such as `length` or `content_filter`), so its answer is a fragment |
| `BackendNotRegistered` | an `invoke` names a provider no backend is registered for, or names none while there is not exactly one backend |
| `WorkflowNotFound` | no file at that path (`workflow.dispatch`, `workflow.describe`, `schedule.create`, a `dispatch` step) |
| `ProtocolError` | the request's envelope or payload is malformed, or an id it names is invalid, taken or missing |
| `JobStoreError` | a job file is missing or unreadable |
| `AgentValidationError` | an `invoke`'s agent cannot be built: its model, tools or `permission_mode`, or a combination its provider cannot run; fix the workflow |
| `AgentSessionMissing` | an `agent` step ran outside an `invoke`, where no agent session is open; fix the workflow |
| `ResourceError` | a file cannot be given: a path with an empty, `.` or `..` part, a workflow path spelled `<inline>`, a `resource.read` path that is absolute, hidden or led out by a link, a missing or unreadable file |
| `ServiceFailed` | the service handling a `service.send` answered with an error; the message is the service's |
| `TokenRejected` | token failed verification; re-issue it and retry once |
| `UnknownMethod` | the daemon does not know the method name |
| `PolicyDenied` | the principal may not dispatch/control that workflow (policy/*.yaml); a retry meets the same refusal |
| `WorkflowValidationError` | a workflow file does not load, has no public `main`, or does not build; fix the file. An inline spec the front end or the load refuses is a `ProtocolError` instead, and an inline spec that does not build fails its run |
| `OutputResolutionError` | an `extract` step's text does not hold what its `outputs` asks (no JSON, a missing mandatory path, a regex that does not match, a value that does not coerce); a `catch` reads it as `extract_refused` |
| `OutputDeclarationError` | an `extract` step's `outputs` is no extractor declaration (a dictionary that is no extractor, the key `_raw`, a path or a regex that does not parse); fix the spec |
| `DaemonShuttingDown` | the daemon is draining for shutdown: it starts no new run (`workflow.dispatch`, a schedule's fire) and no service (`service.run`, `service.restart`) |
| `RunCapExceeded` | the run cap is saturated (backpressure); a later retry can succeed |
| `RunCancelled` | the run was cancelled (`workflow.cancel`, or the daemon shutting down) |
| `InputValidationError` | a run's inputs do not fit what its `main` declares: a name it does not declare, nothing for a parameter that is not Optional, or a value of another type. The run fails before any statement runs; a `dispatch` step whose child refuses its inputs faults, with `ChildRunFaulted`, past any `catch` |
| `InternalError` | a failure neither Forge nor the language names (an error of the system); the message is its text |
| `ChildRunFailed` | a `dispatch` step's child run completed as failed; the message carries the child's error type, and a `catch` reads it as `child_run_failed` |
| `ChildRunFaulted` | a `dispatch` step's child run failed with a failure no `catch` takes (an `InputValidationError`, an `InternalError`, and the like); the message carries the child's error type. A `catch` does not take it |
| `ChildRunCancelled` | a `dispatch` step's child run was cancelled. A `catch` does not take it |
| `UnwritableValue` | the value a run returned has no JSON form (a procedure, or a dictionary two of whose keys are spelled as one text); the run fails with it |
