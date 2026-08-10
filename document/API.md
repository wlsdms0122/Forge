# Forge API Reference

`forge` is an LLM-invocation daemon and its client, shipped as **one binary**.
The CLI is the **single surface** for using forge — every consumer (the Python
runtime, the admin app, workflow subprocesses) invokes the `forge` binary as a
subprocess. Nothing else opens the daemon's Unix socket directly.

```
forge serve                       run the daemon (long-running)
forge <subcommand> ...             client subcommands → JSON-RPC over the socket
```

This document covers the full CLI surface and the JSON-RPC methods underneath.
For the workflow spec (Step / Action / Condition / Expression syntax), see
**[Spec.md](./Spec.md)**.

- [1. Invocation & configuration](#1-invocation--configuration) — version, binary/socket discovery, config, env, global options, exit status
- [2. CLI surface](#2-cli-surface) — [`serve`](#forge-serve) · [`workflow`](#forge-workflow) · [`schedule`](#forge-schedule) · [`job`](#forge-job) · [`resource`](#forge-resource) · [`service`](#forge-service) · [`status`](#forge-status) · [`policy`](#forge-policy) · [`token issue`](#forge-token-issue)
- [3. RPC transport](#3-rpc-transport)
- [4. RPC methods](#4-rpc-methods)

---

## 1. Invocation & configuration

### Version

`forge --version` prints the product version (e.g. `0.1.0`) and exits. The same
version appears in `forge status` under the daemon's identity and in the
session's `runtime.json`, so a client can tell which build a running daemon is.

### Binary discovery

| Source | Used by |
|--------|---------|
| `FORGE_BIN` env | consumers locating the binary; falls back to `forge` on `PATH` |
| `forge` on `PATH` | interactive use |

### Socket discovery

The socket is a pure function of the session — config has no say:

```
socket      = <sessionHome>/forged.sock
sessionHome = <XDG_CONFIG_HOME | ~/.config>/forge/<session>
session     = --session  >  FORGE_SESSION  >  "default"
```

`serve` binds that canonical socket. A client falls back to it but honors
`FORGE_SOCKET` first, so a spawned child reaches the exact daemon that spawned it
without re-deriving the session. A client never reads config.

A *session* names a daemon instance (its public address). Multiple daemons =
distinct sessions; the bundled bot runs the `default` session.

### Config resolution (`serve` only)

The daemon resolves `config.toml` with this precedence — clients are never involved:

```
--config flag  >  <sessionHome>/config.toml  >  FORGE_* env vars  >  built-in defaults
```

env only fills keys that the toml leaves silent (emergency override).

### Config file (`config.toml`)

Everything is optional — each key has a built-in default, so a minimal toml only
declares deviations, managed services, and secrets-by-env. **Path anchoring:**
a relative path written in the toml resolves against the toml's directory;
unspecified catalogs/logs default under `sessionHome`. The runtime dir is
session-owned (`<sessionHome>/runtime`) and not configurable — like the socket.

| Table / key | Default | Meaning |
|---|---|---|
| `[dir]` `workflow`/`schedule`/`resource`/`policy` | `<sessionHome>/<key>` | source catalog roots; a relative value resolves against the toml's directory. |
| `[log]` `jsonl` / `error` | `<sessionHome>/log/forge.log.jsonl` · `…/error.log` | structured + stderr logs |
| `[log]` `maximum_bytes` | `52428800` (50 MiB) | single-file rotation threshold; ≤0 disables rotation |
| `[pool]` `maximum_concurrent_steps` | `4` | concurrent leaf-step (invoke/shell) cap; excess queues FIFO |
| `[providers.<name>]` `kind` (+ settings) | one `claude` (claude-cli) | backend instances. `kind` = `claude-cli` \| `codex-cli` \| `openai-compat`. CLI kinds accept `bin`; OpenAI-compatible accepts `endpoint` and requires an explicit model in each Agent reference. Declaring any drops the built-in claude default — list it explicitly alongside others. API keys via `FORGE_PROVIDER_<NAME>_API_KEY` env only. |
| `[service.<name>]` `command` (+ `cwd`/`env`/`auto_spawn`/`log_file`/`restart_*`) | — (must declare) | managed child processes forge spawns/supervises (§3 of `forge serve -h`) |
| `[hooks]` `logging` | `true` | structured event logging |

The socket is **not** a config key — it lives at `<sessionHome>/forged.sock`
(see *Socket discovery*). Run `forge status` (or `--json`) to print the daemon's
effective config + every key's source (`toml`/`env`/`default`).

### Environment variables

| Var | Meaning |
|-----|---------|
| `FORGE_BIN` | path to the `forge` binary (consumer-side discovery) |
| `FORGE_SESSION` | session name when `--session` omitted — selects which daemon socket |
| `FORGE_SOCKET` | exact socket path; overrides session. Injected into spawned subprocesses |
| `FORGE_RUNTIME` | daemon runtime dir injected into subprocesses for `$FORGE_RUNTIME/scratch/…` artifacts (not socket discovery) |
| `FORGE_ACCESS_TOKEN` | daemon-signed bearer token carried on every RPC — injected into workflow subprocesses at spawn, set by operators for direct use |

### Global options

Every client subcommand accepts these, placed **after** the leaf subcommand
(`forge workflow list --session prod`):

| Option | Meaning |
|--------|---------|
| `--session <name>` | session selecting the daemon socket (default `default`) |
| `--token <token>` | bearer token for the call; overrides `FORGE_ACCESS_TOKEN` |

(To reach a daemon at a non-default socket, set `FORGE_SOCKET` — children inherit it.)

Every RPC requires a token (except read-only `daemon.status`), `token.issue`
included. It is supplied as input — `--token` or the `FORGE_ACCESS_TOKEN` env
var — never minted on the caller's behalf. The first token is the daemon's
boot-minted `system:admin`, handed to its launcher over an inherited fd; from
there issuance is delegation (§5).

### Exit status

| Code | Meaning |
|------|---------|
| 0 | success |
| 1 | daemon boot failure (`serve`) |
| 2 | argument parse error |
| 3 | configuration load failure |
| 4 | payload validation failure (incl. missing token) |
| 5 | RPC error returned by the daemon |
| 6 | RPC rejected for a stale/invalid token — reissue needed |

---

## 2. CLI surface

Output is human-friendly plain text by default; pass `--json` for
machine-parseable output. The "RPC" column links each command to §4.

### `forge serve`

Run the LLM-invocation daemon over a Unix socket. Long-running; owns LLM
backends, workflow execution, schedules, and the ACL gate.

```
forge serve [--session <name>] [--config <config>]
```

`--session` picks where to bind (`<sessionHome>/forged.sock`); `--config` only
locates the daemon's settings/data. Under `<sessionHome>`: `forged.sock` (RPC socket) and
`runtime.json` (self-record: pid, session, socket, resolved paths — written on
boot, deleted on clean shutdown). Refuses to start if a live daemon already holds
the socket. Signals `SIGINT`/`SIGTERM` → graceful shutdown.

### `forge workflow`

Dispatch and inspect workflow runs.

Catalog hot reload applies content edits within the workflow schema understood by
the running daemon; it is not a schema-migration mechanism. A breaking workflow
key change must be deployed as one generation: stop every daemon reading that
catalog, install the matching binary and catalog, then restart. Forge intentionally
does not retain legacy decoder keys solely to bridge a mixed-generation process.

#### `forge workflow dispatch`

Dispatch a workflow run. RPC: `workflow.dispatch`.

```
forge workflow dispatch [<name>] [--spec <spec>] [--inputs <json>]
                        [--parameters <json>] [--correlator <str>]
                        [--origin <json>]
                        [--root-id <id>] [--parent-id <id>]
                        [--async] [--stream] [--json]
```

| Option | Meaning |
|--------|---------|
| `<name>` | registered workflow name (positional). Omit when using `--spec` |
| `--spec` | inline **anonymous** workflow JSON — use instead of the name argument. A `name` key is rejected — the run is named `<inline>` and gated by that sigil |
| `--inputs` | workflow inputs, JSON object (default `{}`) |
| `--parameters` | caller passthrough, JSON object — rides the log envelope only |
| `--correlator` | opaque string — ridden through to handler frames |
| `--origin` | `{"kind":"...","id":"..."}` — what dispatched the run |
| `--root-id` / `--parent-id` | parent node-tree context to inherit (tree root id + parent node) — normally omitted; each run self-roots at its own workflow_id |
| `--async` | return as soon as dispatched (fire-and-forget) |
| `--stream` | stream the run's progress as JSONL (mutually exclusive with `--async`) |

**Blocking vs `--async`** — without `--async`, blocks until the workflow
completes and returns the full result. With `--async`, returns immediately:
`{workflow_id, name, status:"running"}`; the run continues in the background
and is observable in the forge log.

**`--stream`** — keeps the connection open and prints the run's progress as
JSONL, one object per line (RPC: `workflow.dispatch_stream`): first the ack
(`{id, result:{workflow_id, name, status:"streaming"}}`), then
`{"kind":"workflow.event", ...}` lines, then a terminal
`{"kind":"workflow.result","result":{...}}` — same result shape as blocking
dispatch. Child workflows dispatched by the run share its root and stream
too. Disconnecting does **not** cancel the run (use `workflow cancel`).
Implies JSON output.

**`unawaited`** — events of runs this stream's root does not await carry
`"unawaited": true`. A run is unawaited when the path from the root to it
crosses at least one `--async` dispatch edge: whoever sits above that edge does
not wait, so once the root finishes and the subscription closes, the events
still owed below it have nowhere to go. Consumers must not wait forever on a
`started` they saw for such a run — observe its completion by streaming that run
itself, or via `workflow.list_active`.

The flag is one-directional. Its presence means "the terminal may structurally
never arrive here"; its *absence* is **not** a promise of delivery — a cancelled
parent, a crash, or a dropped connection can still cut a stream short. Consumers
need a closing rule of their own for that residue.

`unawaited` is a property of the (stream, run) pair, not of the run: stream the
async run itself and that stream *does* await it. So the fact an event carries is
`"async": true` (this run's birth edge did not await it, and it is not inherited
by its children); `unawaited` is derived per-stream by the relay, which owns the
contract so the derivation is not reimplemented by every consumer. The relay
filters nothing by lineage — unawaited children's events flow like any other, and
what to display is the consumer's call.

**Identity & envelope** — the bearer token carries the caller's identity. A
workflow subprocess's injected token is a `cli:<workflow>` token; trace /
correlator / parameters / origin are then inherited from the parent run
server-side and the corresponding flags are ignored (a nested run cannot forge
its own coordinates). An operator token (`system:*`) carries no parent, so
those flags apply.

#### `forge workflow list`

List registered workflows. Plain output shows one workflow per line; a
trailing `FAILED (N):` block lists files that failed to load (YAML decode
error or validator rejection). RPC: `workflow.list`.

```
forge workflow list [--json]
```

#### `forge workflow describe`

Show one workflow's calling contract — description, source path, inputs
(type / default / hint — a declared default, even `null`, marks it optional),
and outputs mapping. Counterpart to `service describe`. RPC: `workflow.describe`.

```
forge workflow describe <name> [--json]
```

#### `forge workflow active`

Show workflows the pool is currently tracking (queued / running / cancelling).
RPC: `workflow.list_active`.

```
forge workflow active [--json]
```

#### `forge workflow health`

One-shot health check of the workflow pool — slots, waiter ages, run trees,
spawn rate, advisory flags. RPC: `workflow.health`.

```
forge workflow health [--json]
```

#### `forge workflow cancel`

Cancel a queued or running workflow. RPC: `workflow.cancel`.

```
forge workflow cancel <workflow-id> [--json]
```

#### `forge workflow check`

Lint workflow YAML file(s) — runs the same decode + validator the daemon uses
at load time. Local-only; does not contact the daemon. Intended for CI and
pre-commit hooks. **No RPC counterpart.**

```
forge workflow check <path>...
```

For each path: decodes the file as a `Workflow`, then runs
`WorkflowValidator`. A line per file: `✓ <path>` or `✗ <path> — N issue(s)`
followed by indented `<location>: <message>` lines. Exit code 1 if any file
fails, 0 otherwise. Shell globs are expanded by the shell.

Catches: malformed YAML, broken spec structure, half-spelled expression forms
(`{ ref: }` / `{ value: }` / `{ format: }`), `{ ref: inputs.X }` where X is not
declared, `{ ref: X }` where X is not a visible step id, format templates
naming a binding not declared in `with`, and the validator's other shallow
rules.

Does not catch (by design — see [Spec.md: Validation](./Spec.md#validation)):
`{ ref: step.X.Y }` field-level refs, cross-workflow refs (dispatch child
outputs), or any ref whose validity depends on runtime JSON shape.

### `forge schedule`

Inspect, create, and toggle workflow schedules — a single surface covering
both repeating and one-shot fires.

A schedule fires its workflow on a **trigger**, exactly one of:

| flag | format | meaning |
|------|--------|---------|
| `--every` | duration (`30s 5m 1h 2d`, compound `1h30m`) | repeat forever, every interval |
| `--at` | `HH:mm` (24h) + `--timezone` (IANA), optional `--days mon,wed,fri` | repeat on a wall-clock |
| `--once` | `"yyyy-MM-dd HH:mm:ss"` + `--timezone` | fire once at this wall-clock time |
| `--after` | duration (`30s 5m 1h 2d`, compound `1h30m`) | fire once, this much from now (timezone-agnostic) |

A duration is one or more `<int><unit>` tokens (`s`/`m`/`h`/`d`) summed —
`90m` and `1h30m` are both valid; a bare integer is seconds. `--after` is
resolved against the daemon clock at creation and stored as an absolute time,
so the caller never computes wall-clock time itself and a reload never slides
the fire time.

Repeating triggers (`--every`/`--at`) never end (no `until` — bounded
recurrence is not modelled; delete it when done). One-shot triggers
(`--once`/`--after`) fire exactly once and **stay on disk** afterward — the
declaration file is not self-deleted. Fire-state lives in a daemon-owned
ledger (`runtime_directory/fire-ledger.json`), separate from the declaration:
recording it *before* dispatch gives at-most-once (no re-fire if the daemon
dies mid-fire). A spent one-shot created in the runtime dir is auto-GC'd by
the daemon; a hand-authored config one shows `spent` in `list` for you to
remove.

Storage is two directories — an *operational* split, not a domain tier:
`schedule_directory/*.yaml` (git-managed, hand-authored config) and
`runtime_directory/schedule/*.yaml` (daemon-owned, where `create` writes). `delete`/
`set_enabled` act on a schedule regardless of which dir it came from; `create`
only writes to the runtime dir. `set_enabled` never rewrites a declaration
file — it records an override in the daemon-owned ledger
(`runtime_directory/schedule-enabled.json`), and the override is dropped once the
requested value matches the file's declared `enabled` (convergence), so a
hand-edited declaration stays authoritative.

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
ephemeral agent sessions — distinct from a workflow (the action) and a run
(one execution). A ticket is a free-form canvas, not bound to any workflow;
association is observed — when a run's session runs a ticket-targeting
command (`job show` / `job update`), the daemon records the attachment.
`status` is a free string forge never interprets; its vocabulary belongs to
the agents. Every mutation is stamped with the caller token's identity.

| Command | RPC | Notes |
|---------|-----|-------|
| `forge job create --title <t> [--brief --refs --origin --plan --parent-job --status --id] [--json]` | `job.create` | `--refs`/`--plan` take JSON arrays; `--origin` an opaque JSON map |
| `forge job show <id> [--json]` | `job.show` | full ticket: brief, refs, plan, comments, events, children |
| `forge job list [--status <s>] [--origin-key <k> --origin-value <v>] [--json]` | `job.list` | summary rows, newest-updated first |
| `forge job update <id> [--note --brief --ref --ref-note --item --item-desc --item-status --status] [--json]` | `job.update` | field-level ops, append-safe |
| `forge job delete <id> [--json]` | `job.delete` | remove a reviewed ticket (unlinks it from its parent) |

### `forge resource`

Inspect files under `resource_directory`, the anchor for `@<path>` references in workflow prompts
and shell command heads. The daemon's `ResourceStore` is the single gate — anchor and
escape checks and hot reload happen there, and external tools (admin, scripts, agents)
read resources through these RPCs instead of touching the filesystem.

#### `forge resource list`

List files in `resource_directory`. RPC: `resource.list`.

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
| `<path>` | Path relative to `resource_directory`. `..` / symlink escapes are rejected by the daemon |
| `--max-bytes` | Truncation cap, default 64 KiB. Bytes beyond are dropped (a `... (truncated)` marker is appended) and `truncated=true` |

Plain output: body. JSON: `{ "path", "body", "size", "truncated" }`.

### `forge service`

Inspect, register, and call external service handlers, and control the
managed child processes the daemon supervises. An external service handler
(e.g. `slack`) is a process that registers with the daemon and implements a
capability forge itself does not.

#### `forge service list`

List registered service handlers. RPC: `session.list`.

```
forge service list [--json]
```

#### `forge service describe`

Show one handler's call schema — its description and the actions/ops it
accepts, with params and returns. The contract to consult before `forge
service send`. RPC: `session.list` (filtered to one).

```
forge service describe <name> [--json]
```

#### `forge service register`

Run the current process as a service handler — a long-lived **co-process**.
forge owns the socket, the `session.handler.register` handshake, and
reconnect/backoff; the parent process speaks JSON over stdio and never touches
the socket. RPC: `session.handler.register` + `session.handler.ack`.

```
forge service register <name> [--schema <json>]
```

| Option | Meaning |
|--------|---------|
| `<name>` | service name to register (e.g. `slack`) |
| `--schema` | handler schema, JSON object (advertised via `forge service list`) |

The bearer token (`FORGE_ACCESS_TOKEN` / `--token`) is read once at startup.
The daemon binds the handler name to the token's principal: a `service:<name>`
token may only register/ack as that service (a mismatching `<name>` fails
loud), a `cli:*` workflow subprocess is rejected outright, and operator
principals (`system:*`, `admin:*`) may register any name.

| Stream | Content |
|--------|---------|
| stdout | one JSON line per incoming `session.message` frame |
| stdin | one JSON line per ack: `{"message_id":"...","result":{...}}` or `{"message_id":"...","error":{...}}` |

The daemon dropping the connection is invisible to the parent — forge
reconnects and re-registers with exponential backoff. Exits 0 on stdin EOF.
If the daemon restarts and rejects the token (seed rotation), the co-process
exits **6** so the parent can respawn it with a freshly issued token.

#### `forge service send`

Hand a JSON payload to a registered handler. RPC: `session.send`. To run a
workflow use `forge workflow dispatch` — `send` is for external handlers only.

```
forge service send <name> --payload <json> [--async] [--json]
```

`--async` returns as soon as the work is dispatched (`{message_id,
status:"dispatched"}`) instead of blocking for the handler's result. A `wait`
key in the payload is rejected — async-ness is a call-level flag, not payload.

#### Managed-service control

Control the child processes forge itself spawns/supervises (`[service.<name>]`
entries in `config.toml`). Operator surface — a `cli:*` workflow-subprocess
token is rejected; a `service:<name>` token may only act on its own name and
may not use `reload` (global control).

| Command | RPC | Notes |
|---------|-----|-------|
| `forge service run <name> [--json]` | `service.run` | start a managed service |
| `forge service shutdown <name> [--json]` | `service.shutdown` | stop a managed service |
| `forge service restart <name> [--json]` | `service.restart` | stop and start |
| `forge service status [--json]` | `service.status` | supervision state of every managed service |
| `forge service reload [--json]` | `service.reload` | re-read `config.toml`'s `[service.*]` tables and apply the diff |

### `forge status`

Print the daemon's identity (session, version, socket, pid, uptime), its effective
`ForgeConfig` with each value's source (toml / env / default), and runtime counts
(workflows, schedules, jobs, services). RPC: `daemon.status` (token-free). If the
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
requires a presented token, and mints under attenuation — only an admin-tier
presenter (`system:admin` / `admin:<user>`) may delegate (§5).

```
forge token issue <principal> [--json]
```

`<principal>` is required — `system:runner`, `system:admin`, or `admin:<user>`.
There is no default: the issuer states the identity explicitly. See §5 for the
issue gate. The very first token comes from the daemon's boot fd, not this call.

---

## 3. RPC transport

Clients speak **line-delimited JSON-RPC over a Unix domain socket**
(`<sessionHome>/forged.sock`). One JSON object per line, `\n`-terminated.

**Request**

```json
{"id": "<client-id>", "method": "<method>", "params": { ... }}
```

**Response** — success:

```json
{"id": "<client-id>", "result": { ... }}
```

**Response** — error:

```json
{"id": "<client-id>", "error": {"type": "<ErrorType>", "message": "<text>"}}
```

**Streaming methods** (`session.handler.register`, `workflow.dispatch_stream`)
keep the connection open and emit multiple lines: first an ack envelope, then a
stream of frames.

The CLI flattens this — a `--json` command prints the `result` object; an RPC
error becomes a non-zero exit (code 5, or 6 for `TokenRejected`) with the
message on stderr.

---

## 4. RPC methods

Auth column: **token** = a valid bearer token required in `params.token`;
**none** = unauthenticated (read-only). All methods require a token except
`daemon.status` (read-only introspection / liveness). `token.issue` mints under
attenuation from the presenter's principal — §5.

| Method | Auth | Streaming | CLI |
|--------|------|-----------|-----|
| `workflow.dispatch` | token | no | `workflow dispatch` |
| `workflow.dispatch_stream` | token | **yes** | `workflow dispatch --stream` |
| `workflow.list` | token | no | `workflow list` |
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
| `session.send` | token | no | `service send` |
| `session.list` | token | no | `service list` / `service describe` |
| `session.handler.register` | token | **yes** | `service register` |
| `session.handler.ack` | token | no | (internal to `service register`) |
| `service.run` | token | no | `service run` |
| `service.shutdown` | token | no | `service shutdown` |
| `service.restart` | token | no | `service restart` |
| `service.status` | token | no | `service status` |
| `service.reload` | token | no | `service reload` |

### `workflow.dispatch`

Single entry point for all workflow dispatch. Operator/runner/admin fresh-root
calls and nested calls from inside a workflow are distinguished by the **token**.

**params**

| Field | Req | Notes |
|-------|-----|-------|
| `token` | ✅ | identity derived from claims; caller cannot set `principal` |
| `name` | △ | registered workflow name — exclusive with `spec` |
| `spec` | △ | inline anonymous workflow JSON; a `name` key is rejected, run is named `<inline>` |
| `inputs` | — | object, default `{}` |
| `async` | — | bool, default `false` |
| `parameters` / `correlator` / `origin` / `root` | — | honored only for fresh-root tokens; for a workflow-subprocess token they are inherited from the parent `WorkRecord` and caller values are ignored |

`root`: `{"root_id": "...", "parent_id": "..."}` — parent node-tree to attach under. Omit to self-root (the run's node tree roots at its own workflow_id, so `root_id == workflow_id`).
`origin`: `{"kind": "...", "id": "..."}` — what dispatched this run (`manual`/`rpc`/`schedule`/`workflow`). Exposed inside the workflow as `{ ref: origin.kind }` / `{ ref: origin.id }`.

**result** — `async=false`:

```json
{"workflow_id":"...","name":"...","status":"ok"|"failed",
 "duration_ms":1234,"outputs":{...},"error":{"type":"...","message":"..."}}
```

`error` is present only when `status` is `failed`. **result** — `async=true`:

```json
{"workflow_id":"...","name":"...","status":"running"}
```

`running` acknowledges acceptance, not completion. The policy gate is
evaluated before the call returns — a denied principal gets the error
synchronously, never a `running`. A background failure after acceptance is
recorded as a `dispatch.failed` event (error level) in the forge log.

### `workflow.dispatch_stream`

Streaming variant of `workflow.dispatch` — same params (minus `async`), same
identity/envelope/policy rules. The connection stays open for the run's
lifetime and relays its progress:

```json
{"id":"<client-id>","result":{"workflow_id":"...","name":"...","status":"streaming"}}
{"kind":"workflow.event","event":"workflow.started","workflow_id":"...","workflow_name":"...","root_id":"...","ts":...}
{"kind":"workflow.event","event":"step.started","step":"...","action":"shell|invoke|...","node_id":"...","parent_node_id":"...", ...}
{"kind":"workflow.event","event":"step.completed","step":"...","duration_ms":..., "output_preview":"...","output_len":..., ...}
{"kind":"workflow.result","result":{...same shape as blocking dispatch result...}}
```

Event lines are `WorkflowEvent` objects (`workflow.started/completed/failed`,
`step.started/completed/failed/skipped`) filtered to this run's **root** —
child workflows dispatched by the run (a `dispatch` step) inherit the root and
stream too; `root_id`/`node_id`/`parent_node_id` let the consumer rebuild the
tree. A policy denial is returned as a plain RPC error line (no stream). If
the run fails to even start after the ack (e.g. run cap), the terminal
`workflow.result` line carries the real error type in `error.type` — the same
mapping the blocking path's RPC error envelope uses. If the client disconnects
mid-run the run continues (same semantics as `async=true`); interruption is
`workflow.cancel`'s job.

### `workflow.list`

**params** `{"token"}`. **result**

```json
{"workflows":[{"name","description","source"}],
 "failures":[{"path","reason","mtime"}]}
```

`failures` lists `*.yaml` files that couldn't be loaded — YAML decode
error or validator rejection (e.g. a `{ ref: inputs.X }` ref to an
undeclared input). Always present (may be empty); admin surfaces broken
workflows without grep'ing stderr.

### `workflow.describe`

**params** `{"token","name"}`. **result**

```json
{"name","description","source",
 "inputs":{"<key>":{"type","default"?,"hint"?,"oneOf"?}},
 "outputs":{"<key>": <Expression>}}
```

`inputs` is the declared signature map (wire format preserved — keys match
what the workflow YAML declares); `type` ∈
`string|int|double|bool|object|array`, and a declared `default` (even
`null`) marks the input optional. `outputs` is the expression map; each
value round-trips in the expression grammar — a reference comes back as
`{"ref": "<path>"}`, quotation as `{"value": ...}`, interpolation as
`{"format": "...", "with": {...}}`, and records/arrays/literals as
themselves. Empty `inputs`/`outputs` are returned as `{}` (not omitted) so
the caller can iterate without null-checks. Unknown workflow →
ResolutionError `workflow not found: <name>`.

### `workflow.list_active`

**params** `{"token"}`. **result**

```json
{"workflows":[{"workflow_id","workflow_name","origin","principal","state",
               "enqueued_at","started_at","held_slots"}],
 "maximum_concurrent_steps":N,"free_slots":N,"queued_waiters":N}
```

`state` ∈ `queued|running|cancelling`. Times are epoch seconds. `started_at`
is omitted while queued.

### `workflow.health`

One-shot pool health snapshot with advisory flags.

**params** `{"token"}`. **result**

```json
{"slots":{"max":N,"free":N,"waiters":[{"workflow_id","waited_ms"}]},
 "runs":{"active":N,"cap":N,"refused_total":N,
         "oldest":[{"workflow_id","workflow_name","state","age_ms"}],
         "trees":[{"root_id","runs":N,"names":[...]}]},
 "dispatch":{"last_60s":N},
 "flags":[{"kind":"...","class":"saturation|anomaly", ...}]}
```

`flags` are threshold-derived advisories: `long_wait` (a waiter queued ≥60s),
`long_run` (a run alive ≥30min), `big_tree` (≥16 runs under one root),
`high_rate` (≥30 dispatches in 60s), `runs_refused` (any refusal in 60s).
Each flag carries the fields of the row that tripped it.

### `workflow.cancel`

**params** `{"token","workflow_id"}`. **result** `{"cancelled":bool,"workflow_id"}`.
`cancelled=false` means the id was already unregistered (finished/failed).
Cancelling a live run is gated by policy on that run's workflow name — the
same dispatch ACL, so a principal that may not dispatch a workflow may not
cancel its runs either.

### `schedule.list`

**params** `{"token"}`. **result**

```json
{"schedules":[{"id","workflow","trigger","concurrency","enabled",
               "runtime":bool,"inputs","source","next_fire_at"?,
               "last_attempt_at"?,"last_outcome"?,"outcome_at"?,"reason"?,"spent"?}],
 "failures":[...],"flags":[{"kind":"schedule_denied","schedule_id","reason"?,"outcome_at"?}]}
```

`trigger` is the trigger dict — one of `{"every":"1h"}`,
`{"at":"09:20","days":["mon",…]?,"timezone":"Asia/Seoul"}`, or
`{"once":"2026-06-20 09:00:00","timezone":"Asia/Seoul"}`. All schedules appear
(repeating + one-shot). `next_fire_at` is a UTC ISO8601 display estimate
(absent for a spent one-shot). `last_attempt_at` is the last consumed fire
slot (from the ledger — an *attempt*, recorded before dispatch for
at-most-once, so it advances even when the fire could not launch);
`last_outcome` is that slot's disposition — `launched` (the scheduler committed
the slot to the run chain; the run's *start* is the `schedule.fired` log event
with its runID, and success/failure is the run's own record — the vocabularies
are split because the axes differ), `denied` (the fire could not launch —
machine-readable `reason`: `workflow_missing` / `workflow_invalid` /
`spec_decode`), or `skipped` (concurrency policy dropped it — a normal
disposition, not a failure). `last_outcome: "unknown"` = the disposition is
permanently unknowable (pre-upgrade ledger entry, or a crash between attempt
and close) — reported as a value so it stays distinguishable from a clean
close; the field is absent only while an attempt is in flight.
`last_attempt_at` is the wall-clock moment of the attempt (the phase anchor
slot is internal — after downtime catch-up the two differ). `spent` (one-shot only)
is true when its slot was consumed and it won't fire again — an attempt
consumes the slot even if it was denied; a denied runtime one-shot is *not*
auto-collected (it stays listed with its flag, like a spent config one-shot,
until a human removes it). `flags` mirrors `workflow.health` advisory
conventions: `schedule_denied` marks schedules whose latest slot could not
launch, so a permanently-broken schedule is visible at a glance; it clears on
the next successful fire. `runtime` flags origin (true = created via
`schedule.create`).

### `schedule.set_enabled`

**params** `{"token","id","enabled":bool}`. **result** `{"id","enabled"}`.
Gated by the dispatch ACL on the schedule's target workflow.

### `schedule.create`

Creates a schedule in `runtime_directory/schedule` (daemon-owned). Fails if the `id`
collides, the named `workflow` is not registered, the inline `spec` fails
decode/validation, or the caller's principal is not allowed to dispatch the
target workflow (`policy/*.yaml`, checked against the resolved name —
`<inline>` for a spec). The principal is not stored; fires run as
`system:schedule:<id>` — authorization is a creation-time concern only.

Fire target via `workflow` (registered name) or `spec` (anonymous inline) —
same rules as `workflow.dispatch`: mutually exclusive, `spec` rejects a
`name` key and is anonymized to the `<inline>` sigil. The spec is decoded
and run through `WorkflowValidator` at create time so failures surface up
front rather than at fire time. The spec is stored on the schedule record
and re-decoded on every fire.

**params**

| Field | Req | Notes |
|-------|-----|-------|
| `token` | ✅ | any authenticated token |
| `workflow` | △ | registered workflow name — exclusive with `spec` |
| `spec` | △ | inline anonymous workflow JSON — `name` key rejected, run as `<inline>` |
| `every` | △ | interval duration (`"30s" "5m" "1h" "2d"`) — repeating |
| `at` | △ | wall-clock `"HH:mm"` (24h) — repeating; requires `timezone` |
| `once` | △ | wall-clock `"yyyy-MM-dd HH:mm:ss"` — one-shot; requires `timezone` |
| `after` | △ | relative duration — one-shot; resolved at creation, stored as absolute |
| `timezone` | △ | IANA id (`"Asia/Seoul"`) — required with `at`/`once`; not used by `every`/`after` (`after` displays in UTC) |
| `days` | — | weekday filter for `at` (`["mon",…]`); omit for every day |
| `id` | — | string; auto-generated (`s-<ts>-<rand>`) if omitted |
| `concurrency` | — | `queue` \| `skip` \| `replace`, default `queue` |
| `inputs` | — | object passed to the workflow on fire |

Exactly one of `every` / `at` / `once` / `after`. **result**
`{"id","workflow","trigger","runtime":true,"fire_at"?}` (`fire_at` present for
one-shot; `workflow` is the sigil `<inline>` when created with `spec`).

### `schedule.delete`

Deletes a schedule by id — regardless of which directory it came from (no
tier protection). Deleting a git-managed config file removes it from the
working tree; the next deploy restores it. Gated by the dispatch ACL on the
schedule's target workflow.

**params** `{"token","id"}`. **result** `{"id","deleted":true}`.

### `job.create`

Create a work ticket.

**params**

| Field | Req | Notes |
|-------|-----|-------|
| `token` | ✅ | any authenticated token |
| `title` | ✅ | human-readable title |
| `brief` | — | self-contained brief (default `""`) |
| `refs` | — | array of `{"ref","note"?}` objects or plain strings |
| `origin` | — | opaque JSON map (forge-agnostic; e.g. slack `{channel, thread_ts}`) |
| `plan` | — | array of `{"id"?:int,"desc","status"?}` objects or plain strings; omit `id` to auto-number |
| `parent_job` | — | parent ticket id — must exist; the child is linked into its `children` |
| `status` | — | free string, default `"open"` |
| `id` | — | string; auto-generated (`j-<rand>`) if omitted |

**result** `{"job_id","id","title","status"}`.

### `job.show`

**params** `{"token","id"}`. **result** `{"job":{...}}` — the full ticket
(title, status, brief, refs, plan, comments, events, children, created/updated
stamps) plus derived `open` (an opening event with no terminal yet) and, when
the ticket has children, `children_detail` (`[{"id","title","status"}]`, or
`{"id","status":"missing"}` for a dangling link). When called by a live run's
token, the daemon records the attachment as a touch event. Unknown id →
ProtocolError `job not found: <id>`.

### `job.list`

**params** `{"token","status"?,"origin_key"?,"origin_value"?}` — `status`
filters on the exact status string; `origin_key`+`origin_value` filter on an
origin-map entry. **result**

```json
{"jobs":[{"id","title","status","updated_at","open",
          "last_event"?,"parent_job"?,"children"?,"origin"?}]}
```

Sorted by `updated_at`, newest first.

### `job.update`

Field-level edits — each present param applies independently (append-safe;
several runs may update one ticket concurrently).

**params** `{"token","id"}` plus any of: `note` (append a comment), `brief`
(set/replace), `ref` + `ref_note`? (append a reference pointer), `item` (int
plan-item id) + `item_status`? (default `"done"`) + `item_desc`?, `status`
(set the overall status). When called by a live run's token, the daemon
records the attachment as a touch event.

**result** `{"id","status"}`.

### `job.delete`

**params** `{"token","id"}`. **result** `{"id","deleted":true}`. Removes the
ticket and unlinks it from its parent's children.

### `resource.list`

**params** `{"token"}`. **result** `{"resources":[{"path","size","mtime"}]}`.

`path` is relative to `resource_directory`; `mtime` is ISO8601. Sorted by path.

### `resource.read`

Read one file under `resource_directory`. `..`/symlink escape is rejected by the
daemon; oversize bodies are truncated and `truncated=true`.

**params**

| Field | Req | Notes |
|-------|-----|-------|
| `token` | ✅ | any authenticated token |
| `path` | ✅ | relative to `resource_directory` |
| `maximum_bytes` | — | truncation cap; default 64 KiB |

**result** `{"path","body","size","truncated"}`. `size` is the full
(untruncated) byte count; a truncated `body` ends with a `... (truncated)`
marker line.

### `policy.list`

**params** `{"token"}`. **result**
`{"policy":{"<principal-pattern>":["<workflow-pattern>"]},"failures":[{"path","reason","mtime"}]}` —
`failures` lists policy files that couldn't be loaded (same convention as
`workflow.list`).

### `policy.check`

**params** `{"token","principal","workflow"}`. **result**
`{"principal","workflow","allowed":bool}`.

### `token.issue`

**params** `{"token","principal"}`. **result** `{"token","principal"}`.

Requires a presented token and mints under attenuation — only `system:admin` /
`admin:*` presenters may delegate (§5). Issuable principals: `system:runner`,
`system:admin`, `admin:*`.

### `session.send`

Send a payload to a registered external handler.

**params** `{"token","service","payload","async":bool?}`.

**result** — `async=false`: the handler's ack result (handler-defined).
`async=true`: `{"service","message_id","status":"dispatched"}`.

### `session.list`

**params** `{"token"}`. **result** `{"services":[{"service","schema"?}]}` —
registered external handlers only, sorted by name; `schema` is present only
when the handler advertised one.

### `session.handler.register` (streaming)

Register an external service handler on a long-lived connection.

**params** `{"token","service","schema":object?}`. The handler name is bound
to the verified principal: a `service:<name>` token may only register as that
service (mismatch fails loud), `cli:*` is rejected (a workflow subprocess
cannot register a handler), operator principals may register any name.

**flow**

```
client → daemon : {"method":"session.handler.register","params":{...}}
daemon → client : {"id":<req.id>,"result":{"registered":true,"service":"..."}}   ← ack
daemon → client : {"kind":"session.message","service","message_id",
                   "envelope":{...},"payload":{...}}                            ← repeats
client → daemon : {"method":"session.handler.ack","params":{...}}               ← same connection
```

The `envelope` carries forge's server-side coordinates:
`{workflow_id, origin, root_id?, id?, correlator?}`. The `payload` is
caller-sent and opaque to forge. Closing the connection unregisters the service.

### `session.handler.ack`

Acknowledge a processed `session.message`.

**params** `{"token","service","message_id","result":object?}` — or `"error"`
instead of `"result"`. **result** `{"ok":true}`. Same principal↔service
binding as register — a `service:<name>` token cannot deliver results for
another service.

### `service.run` / `service.shutdown` / `service.restart`

Start / stop / restart a managed service (a `[service.<name>]` entry in
`config.toml`). Operator methods — a `cli:*` token is rejected; a
`service:<name>` token may only act on its own name.

**params** `{"token","name"}`. **result** — the service's status record:
`{"name","state","auto_spawn","crashes","pid"?,"started_at"?,"last_exit_code"?}`.

### `service.status`

**params** `{"token"}` (any authenticated token). **result**
`{"services":[{...status record...,"registered":bool}]}` — one row per
managed service; `registered` is whether a live handler of that name is
currently registered on the session bus.

### `service.reload`

Re-read the daemon's `config.toml`, apply the `[service.*]` diff (removed
services are stopped, added `auto_spawn` ones started), and refresh the
config snapshot. Global service control — rejected for both `cli:*` and
`service:*` tokens.

**params** `{"token"}`. **result**
`{"reloaded":true,"added":[...],"removed":[...],"changed":[...]}`.

---

## 5. Authentication

Every RPC carries a bearer token in `params.token`. The token *is* the
request's identity — forge verifies its signature and reads `principal` from
its claims; it never inspects who the OS-level caller is. A request without a
valid token is rejected. forge does not mint a token on the caller's behalf:
the token is supplied as input (`--token` / `FORGE_ACCESS_TOKEN`), obtained
beforehand from `token.issue` (which itself requires a token) or, for the very
first token, from the daemon's boot fd handed to its launcher.

### Token model

The daemon signs tokens with a random seed minted at boot and held only in
memory: `base64(claims).base64(HMAC-SHA256(claims, seed))`. Claims carry the
`principal` and, for workflow-subprocess tokens, a `workflow_id`.

- **Unforgeable** — only forge knows the seed.
- **Revocation by restart** — a daemon restart rotates the seed, invalidating
  every outstanding token. A rejected token surfaces as `TokenRejected` (CLI
  exit 6); the holder re-issues and retries.

### Carrying the token

- **Workflow subprocess** — the daemon mints a `cli:<workflow>` token at spawn
  and injects it as `FORGE_ACCESS_TOKEN`. Never issuable over RPC.
- **admin** — the daemon's launcher; receives the boot-minted `system:admin`
  token over an inherited fd (`FORGE_BOOTSTRAP_FD`) and delegates from it.
- **runner / managed services** — receive an injected `FORGE_ACCESS_TOKEN` from
  their launcher (admin issues `system:runner` for the runner; the supervisor
  injects `service:<name>` for managed services). They do not self-issue. On
  `TokenRejected` (forge restart) the launcher re-mints and respawns them.

### Issuing tokens (`token.issue`)

`token.issue` is a normal authenticated RPC — it requires a presented token and
mints under **attenuation**, **both** must hold:

1. the requested principal is in the issuable set (`isIssuable`), and
2. the presenter's principal may delegate it (`canIssue`) — only `system:admin`
   and `admin:<user>` qualify.

A workflow subprocess only ever holds a `cli:*` token (re-minted fresh at every
process boundary), and `cli:*` may delegate nothing — so an LLM cannot escalate,
regardless of how it reaches the socket. There is no peer-credential gate; the
unforgeable token *is* the identity.

The bootstrap exception is the **boot** mint, not this RPC: at startup the daemon
mints one `system:admin` token and writes it to the fd named by
`FORGE_BOOTSTRAP_FD` (its launcher's pipe), then closes it — never to disk, never
to a child's environment. Launching the daemon is the root of trust. With no such
fd and an interactive tty it prints to stdout; otherwise it withholds the token.

Issuable principals: `system:runner`, `system:admin`, `admin:*` — stated
explicitly by the issuer (no default). `cli:<workflow>` tokens are minted
internally at workflow-subprocess spawn, never over RPC.

### Principal classes

| Principal | Origin |
|-----------|--------|
| `cli:<workflow>` | workflow subprocess (daemon mints at spawn) |
| `service:<name>` | managed service subprocess (supervisor mints at spawn; never issuable over RPC). Bound to its own name on named service surfaces (handler register/ack, service.run/shutdown/restart) and rejected on global service control (service.reload) |
| `system:rpc` | unauthenticated external RPC |
| `system:runner` | slack / runner pipeline |
| `system:admin` | admin route (manual triggers) |
| `system:schedule:<id>` | the daemon's internal scheduler (repeating + one-shot fires) |
| `admin:<user>` | authenticated admin (future) |
| `runner:<worker>` | authenticated runner (future) |

---

## 6. Policy / ACL

Every `workflow.dispatch` — operator, runner, admin, or a nested call from
inside a workflow — is gated by the policy store.

- YAML files (`*.yaml`) under the policy dir (`[dir] policy`, default
  `<sessionHome>/policy`). Each file is a flat mapping of **principal
  patterns** to lists of **workflow-name patterns**.
- Multiple files are union-merged by principal key. Changes hot-reload on the
  next dispatch — no daemon restart.
- No rules (empty or missing policy dir) → closed-by-default → **every**
  `workflow.dispatch` denied.

**Pattern matching**

| Pattern | Matches |
|---------|---------|
| `cli:response` | exact |
| `cli:*` | class wildcard |
| `*` | global wildcard |

Workflow-name patterns likewise support exact, `prefix.*`, and `*`.

Inline specs (`workflow.dispatch` with `spec`) are anonymous — the caller
cannot choose the name, so they are gated under the fixed sigil `<inline>`.

```yaml
"system:*":     ["*"]
"cli:response": ["bank-jira-sync", "<inline>"]
```

Inspect with `forge policy list` / `forge policy check`.

---

## 7. Error types

The error envelope is `{"type": "<ErrorType>", "message": "<text>"}`.

| Type | Meaning |
|------|---------|
| `BackendTimeout` | a backend call exceeded its timeout — retry candidate |
| `BackendNonzeroExit` | a backend exited non-zero (also carries `exit_code`, `stderr`, `stdout`) |
| `BackendUnavailable` | a backend could not be reached (e.g. an OpenAI-compatible endpoint refused or errored) |
| `MalformedOutput` | a backend response was not the promised shape |
| `ResolutionError` | provider/workflow spec invalid, or workflow not found |
| `ProtocolError` | request envelope / payload malformed |
| `TokenRejected` | token failed verification — re-issue and retry once |
| `UnknownMethod` | the daemon does not know the method name |
| `PolicyDenied` | the principal may not dispatch/control that workflow (policy/*.yaml) — retry is pointless |
| `WorkflowValidationError` | the workflow definition failed validation (inline spec or broken catalog file) — fix the spec |
| `InputValidationError` | a dispatch input violated the workflow's declared ParamSpec |
| `RunCapExceeded` | run cap saturation (backpressure) — retry later is meaningful |
| `ChildRunFailed` | a `dispatch` step's child run completed as failed — message carries the child's error type |
