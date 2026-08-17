# Workflow Spec

Reference for the workflow YAML format. Companion to `API.md` (which covers
the RPC/CLI surface). The live source of truth is the Swift decoder — the
`Spec` kernel (`package/Sources/Spec`) plus the Forge host actions
(`package/Sources/Forge/Service/Workflow/Host`); this document tracks it.

- [Top level](#top-level)
- [Inputs — the signature](#inputs--the-signature)
- [Step — the execution unit](#step--the-execution-unit) · [`rescue`](#rescue--the-catch-block)
- [Kernel actions](#kernel-actions) — [`value`](#value) · [`group`](#group) · [`branch`](#branch) · [`loop`](#loop) · [`each`](#each) · [`parallel`](#parallel) · [`use`](#use) · [`abort`](#abort)
- [Host actions](#host-actions) — [`shell`](#shell) · [`invoke`](#invoke) · [`agent`](#agent) · [`dispatch`](#dispatch) · [`resource`](#resource) · [`dynamic`](#dynamic)
- [Condition](#condition)
- [OutputSpec — `shell.outputs` extractors](#outputspec--shelloutputs-extractors)
- [Top-level `outputs`](#top-level-outputs)
- [Expression — the value language](#expression--the-value-language)
- [Scope at evaluation time](#scope-at-evaluation-time)
- [Validation](#validation)

Spec files are YAML (`*.yaml`), decoded with Yams. YAML comments (`#`) are
allowed, and multiline strings can be written with block scalars (`|`). (The
inline `--spec` passed over IPC/CLI stays a JSON object — that wire format is
unchanged; only the on-disk spec file format is YAML.)

> **Scalar typing — YAML notation, JSON semantics.** Untyped value positions
> (parameter `default`s, `arguments:` maps, condition operands, record/array
> literals) are typed by **JSON literal rules**, not YAML 1.1 resolution:
> only lowercase `true`/`false`, `null`/`~`/empty, and JSON-shaped numbers
> (no leading zeros) are typed — everything else is a string. So unquoted
> `no`, `on`, `09:20`, `007`, `1.10.2` are all **strings**; no quoting
> needed. Any quoted or block scalar is always a string, even `"true"`.
> This matches the inline `--spec` wire (JSON), so a value means the same
> thing in a file and over RPC.

> **The filename is the catalog key.** A definition's identity (`name` for
> workflows, `id` for schedules) is its file's basename — the file body
> does not carry it. A body that does claim a `name`/`id` must agree with
> the basename; a disagreeing claim is a load failure, surfaced loud in
> `*.list` failures. (Inline wire specs are a different shape: they have
> no file, forbid `name`, and are stamped `<inline>`.) Keying by filename
> lets the stores attribute even *undecodable* files to their key (the
> filename still reads), so one broken file blocks only its own id — not
> every create — and a broken deployment resolves as `invalid`, never
> masquerading as `missing`. Subfolders are organization only; the same
> basename in two folders is an identity collision (both excluded, loud).
> Renaming a file is **not** an identity rename — it is old-delete +
> new-create, and per-identity state (fire ledger, overrides) does not
> follow across.

> **Unknown keys are load errors.** Every object in the grammar rejects keys
> it does not know, with a message listing what it does. There is no silent
> tolerance and no backward-compatibility fallback anywhere in the decoder:
> a spelling either is the grammar or fails the load.

## Top level

```yaml
# identity = file basename (<workflow-name>.yaml)
description: ...
parameters:
  <key>: <Parameter>
body:
  - <Step>
result:
  <key>: <Expression>
```

Required: `steps`. Everything else is optional.

Absent `parameters:` means an **empty signature**, not an absent contract — a
spec that declares nothing takes nothing, so a stray caller input is rejected
instead of leaking into scope.

`name` is metadata: the kernel derives identity from the store key (the file
basename), never from the body. Inline anonymous specs (`workflow.dispatch
--spec` or a `dispatch` step's `spec`) carry no `name` and are stamped
`<inline>` by the daemon.

There is no whole-workflow `timeout` field. Deadlines are per action —
`shell`, `invoke`, and `dispatch` each take a `timeout` (seconds); see those
actions. Runaway protection beyond that (observation, cancellation) is the
operator's surface (`workflow.health`, `workflow.cancel`), not a spec field.

## Inputs — the signature

Shorthand (bare type string):

```yaml
workspace: string
```

Full form:

```yaml
channel:
  type: string
  default: general
  oneOf: [general, random]
  hint: "Slack channel name without #"
```

| Field | Type | Notes |
|-------|------|-------|
| `type` | `string` / `int` / `double` / `bool` / `object` / `array` | required. **Enforced at the scope boundary**: a value whose JSON type mismatches is rejected with `InputValidationError` before any step runs. Numeric values normalize to the declared representation — an integral double settles as `int`, an int settles as `double`. |
| `default` | any | fallback when the caller omits the slot. There is no separate `required` field — a declared `default` (even `null`) makes the slot optional; leaving `default` out entirely makes it mandatory. |
| `oneOf` | array of strings | enum constraint (camelCase, unlike the condition grammar's snake_case keys). Enforced at settle: a value outside the set is rejected with `InputValidationError`. |
| `hint` | string | human description (`describe` surfaces this) |

`default: null` is not the same as omitting `default` — it declares "this
slot's default is the absent marker," making the input optional. Omitting
`default` entirely leaves the slot **mandatory**: a caller that does not
supply it is rejected at the boundary, before any step runs. Every missing
name is reported at once.

**A value that is nothing was not given.** A key left out and a key present
with `null` take the same road: both are filled from `default`, and both are
refused when there is no `default`. Telling them apart would make an optional
impossible to forward down a call chain — a parent that did not receive one
passes `null`, and the callee's own `default` has to still apply. (So `null`
cannot be used to *erase* a non-null default; that spelling does not exist.)
An empty string (`""`) is a real value, not an absent marker — it is checked
like any other.

Inputs **settle once** at the scope boundary: inside the scope, references
read the settled values instead of re-evaluating, and only declared names
exist.

## Step — the execution unit

```yaml
- id: search
  when: <Condition>        # optional gate — skipped step outputs null
  rescue: [ <Step>, ... ]  # optional alternate program on recoverable failure
  <action>: <...>          # exactly one action key
```

A step is an envelope (`id`, optional `when`, optional `rescue`) around
**exactly one** action key. The kernel's actions are `value` / `group` /
`branch` / `loop` / `each` / `parallel` / `use` / `abort`; the Forge host
adds `shell` / `invoke` / `agent` / `dispatch` / `resource` / `dynamic`.
Zero or two action keys on one step is a load error.

`when` gates the step: if the condition answers false, the step is skipped
and its output is `null`.

### `rescue` — the catch block

`rescue` is a list of steps — an alternate program, not a substitute value.
If the step fails **recoverably**, the rescue steps run in the enclosing
scope and the rescue's last output becomes the step's output. An empty
`rescue: []` is rejected at load: it would swallow a failure into `null`
without a trace — if the alternate path produces nothing, the honest form is
no rescue at all.

What rescue may absorb is exactly the **recoverable** class — failures whose
cause lies in the executed content or the outside world:

- `abort` (the author's own thrown reason)
- a reference whose upstream never produced the value (`ReferenceNotFound`)
- a nonzero shell exit (`BackendNonzeroExit`)
- a failed child run from `dispatch` (`ChildRunFailed`)
- an exhausted loop budget (`LoopGuardExceeded`)
- a parallel step whose failed children all failed recoverably
  (`ParallelFailed`)
- an expired action deadline (`HostTimeout`)

**While the rescue runs, the failure is a value**: the executor binds the
failure's payload under the failed step's id, so rescue steps can read what
went wrong — `{ ref: risky.message }`, a shell failure's
`{ ref: risky.stderr }`. The moment the rescue answers, the id is rebound to
the rescue's output, so the payload never leaks past the rescue. Every
payload carries `type` and `message`; each failure adds its own fields:

| `type` | extra fields |
|--------|--------------|
| `aborted` | — |
| `reference_not_found` | `path` |
| `loop_guard_exceeded` | `limit` |
| `parallel_failed` | `failures` (child id → reason) |
| `nonzero_exit` | `exit_code`, `stderr`, `stdout` |
| `child_run_failed` | — |
| `timeout` | `seconds` |

Author mistakes and engine faults — shape misuse (`ReferenceUnfit`),
contract violations, misconfiguration, unclassified exceptions — are never
absorbed and propagate loud. **Cancellation** is an instruction, not an
outcome: rescue never runs for a cancelled step.

## Kernel actions

### `value`

The identity action — the step's output is the expression's value.

```yaml
- id: greet
  value: { format: "hello, ${name}", with: { name: { ref: who } } }
```

### `group`

A named sub-scope: steps run in sequence and the group speaks with one
output — the explicit `output` expression (resolved in the group's scope) or,
absent that, the last step's output. Child outputs live in the sub-scope and
do not leak to the parent; only the group step's own output is exposed.

```yaml
- id: blk
  group:
    body: [ <Step>, ... ]
    result: <Expression>   # optional
```

### `branch`

Conditional then/else.

```yaml
- id: pick
  branch:
    when: <Condition>
    then:
      body: [ <Step>, ... ]
      result: <Expression>  # optional
    else:                    # optional
      body: [ <Step>, ... ]
      result: <Expression>
```

Each arm is a sub-scope like `group`. The taken arm's `output` (or `null`
without one) becomes the branch step's output; a false condition with no
`else` outputs `null`.

### `loop`

Repeat `steps` **while `where` holds** — a `while` loop, not a retry
primitive. Each round binds `<step-id>.index` (0-based) before evaluating
`where`, so the condition and the body can read the round counter.

```yaml
- id: gate
  loop:
    where: { of: { ref: "gate.index" }, is_not: 2 }
    body: [ <Step>, ... ]
    guard: 5               # optional iteration budget
    result: { ref: latest } # optional, resolved when the loop ends
```

- When `where` first answers false, the loop ends and `output` (resolved in
  the final round's scope) becomes the step's output — `null` without one.
  If `where` is false immediately, the body runs zero times.
- `guard` is an optional positive iteration budget. Exceeding it throws
  `LoopGuardExceeded` — recoverable, so a `rescue` can express "gave up but
  continue." Without `guard` the language does not prevent an author's
  infinite loop, any more than Swift does; deadlines and observation are the
  host's concern.
- Iterating over material the spec already holds is `each`, whose structure
  guarantees termination without a budget.

**Visibility is two-layered**, and the layers answer different questions:

- *Load time* — `where` and the body are validated against the scope
  **outside** the loop: names declared before the loop step, plus
  `<step-id>.index`. A body step's id is not visible to `where` at load
  time; to be readable there, the name must already exist outside.
- *Run time* — the loop keeps one frame across rounds. When a body step
  rebinds a name the frame already holds (the same `id:` spelled again),
  the next round's `where` — and the next round's body — see the new
  value. When the loop ends the frame is discarded; the outer binding is
  untouched.

Together these produce the validate-and-retry idiom: **run the first check
once, outside the loop; the body rebinds the same id**:

```yaml
- id: checked                # first verdict, outside — makes the name visible
  shell: { command: [jq, -e, "."], stdin: { ref: draft } }
  rescue:
  - id: mark
    value: { format: "RETRY: ${why}", with: { why: { ref: checked.stderr } } }
- id: gate
  loop:
    where: { of: { ref: checked }, starts_with: "RETRY: " }
    guard: 3
    body:
    - id: fix
      agent: { format: "invalid — ${e}. fix it.", with: { e: { ref: checked } } }
    - id: checked             # rebinds — next round's `where` sees this one
      shell: { command: [jq, -e, "."], stdin: { ref: fix } }
      rescue:
      - id: mark
        value: { format: "RETRY: ${why}", with: { why: { ref: checked.stderr } } }
    result: { ref: checked }
```

Inside an `invoke` group the regenerating `agent` turn **continues the same
LLM session** (it does not re-send the prior output; the session remembers
it). Note `output` resolves in the final round's frame, so it may name the
rebound id; if the loop runs zero rounds, the frame holds only the outer
bindings — an `output` naming a body-only id would fail as an absent
reference, which is why the idiom seeds every rebound name outside first.

### `each`

One round per element of `in` — `loop`'s structurally-terminating sibling.
Each round binds `<step-id>.item` and `<step-id>.index`; with `output`, the
per-round results collect into the step's output array (without it, `null`).

```yaml
- id: walk
  each:
    in: { ref: items }   # must resolve to an array
    body:
      - id: tagged
        value:
          format: "${index}:${item}"
          with:
            index: { ref: walk.index }
            item: { ref: walk.item }
    result: { ref: tagged }
```

`in` resolving to a non-array is `ReferenceUnfit` (shape misuse), not an
empty iteration.

### `parallel`

`each`'s concurrent twin — a map over static branches instead of a list.
Children run concurrently, each against a **copy** of the parent scope; no
scope merge exists, so siblings cannot see each other, and the step speaks
with one value: an object of child outputs keyed by child id
(`{ ref: par.left }`).

```yaml
- id: par
  parallel:
    - id: left
      value: 1
    - id: right
      value: 2
```

Child ids must be distinct and the list non-empty. Failure composition
follows the rescue stamp: if every failed child failed recoverably the
composite `ParallelFailed` is recoverable; one author mistake makes the
whole step an author mistake — a rescue must not absorb a typo because a
sibling happened to time out.

### `use`

Call another spec **in-process, against its signature** — the language's
function call (`dispatch` is `Process.run`; see below). Inputs settle at the
callee's boundary; the callee's declared outputs come back as this step's
output object.

```yaml
- id: sub
  use:
    spec: child
    parameters:
      who: { ref: who }
```

### `abort`

The language's `throw` — end the flow here with a reason (the expression is
the message). Recoverable: a `rescue` on the aborting step, or a caller that
treats the failure, may absorb it; unhandled, the run fails with the message.

```yaml
- id: stop
  abort: { format: "unsupported kind: ${k}", with: { k: { ref: kind } } }
```

## Host actions

### `shell`

```yaml
- id: build
  shell:
    command: [swift, build, --package-path, package]  # array of expressions
    cwd: <Expression>          # optional
    env: { <key>: <Expression> }  # optional
    stdin: <Expression>        # optional
    outputs: { <key>: <OutputSpec> }  # optional stdout extractors
    timeout: <seconds>         # optional deadline
```

`command` is an argv array (never a single shell string — nothing is
re-parsed through a shell). Element `[0]` is the executable. A nonzero exit
throws `BackendNonzeroExit` carrying `{exit_code, stderr, stdout}` —
recoverable. On success the output is the stdout decomposed by `outputs`
extractors, or raw stdout without any.

*Forge never inserts a shell — but you may ask for one.* Argv-only means no
string is silently re-parsed; it does not mean shell logic is unavailable.
Naming a shell as the executable is the sanctioned escape hatch, with data
crossing into it through `env` (never by splicing into the script text):

```yaml
- id: cmd
  shell:
    command:
    - /bin/sh
    - -c
    - { value: 'printf "%s%s" "${V:-}" "${U:+ --url $U}"' }
    env:
      V: { ref: version }
      U: { ref: slackURL }   # absent → the whole flag vanishes
```

The `{ value: }` quotation is required exactly because the script text
contains `${` — the loader refuses a bare string that *looks* like it wants
interpolation, and quoting declares "this text is verbatim; the `$` syntax
belongs to the shell." The injection guarantee holds: the script is a
literal the author wrote, and values cross into it as environment
variables, quoted by the shell itself — never spliced into the script text.

`shell` and `agent` are the slot-taking leaves: each acquires a slot from
the global pool (`maximum_concurrent_steps`) for the duration of its work.
`timeout` bounds the work itself; expiry throws `HostTimeout` (recoverable).

### `invoke`

The agent **session envelope** — not a plain group. It resolves the session
settings at its boundary, opens the ambient session through the host, and
runs its steps inside; `agent` steps only make sense in here.

```yaml
- id: talk
  invoke:
    model: claude              # "<provider>[:<model>]"
    allowed: [ files.read, { command: "git status *" } ]
    env_extra: { <key>: <Expression> }
    cwd: <Expression>
    permission_mode: <bypass|safe|restrict>
    share_session: <bool>
    timeout: <seconds>
    body: [ <Step>, ... ]     # agent turns and anything between them
    result: <Expression>       # optional; default = last step's output
```

`model` is `"<provider>[:<model>]"`. The provider (backend registry key,
e.g. `claude`/`codex`) is required — Forge never chooses a provider. The
model half is optional: `"codex"` preserves that backend's native default;
`"codex:gpt-5"` names one. OpenAI-compatible requests are the deliberate
exception: their translator requires an explicit model and rejects
provider-only references instead of inventing a Forge-side default.

At the backend boundary, Forge records the translated `ModelReference` as
provider plus model. When a provider-only selector leaves the model unknown,
the reference remains `backend_default` (`codex:default` in logs) rather
than inventing a name. Provider-native usage keys are translated once into
`input_tokens`, `output_tokens`, `cache_write_tokens`, `cache_read_tokens`,
and `reasoning_output_tokens`; callers without a known price remain
explicitly unpriced instead of being counted as zero-cost.

Agent tools use Forge domain terms, never provider product names:
`files.read`, `files.write`, `web`, `delegate`, `schedule`,
`{ command: <argv-pattern> }`, and `{ mcp: <pattern> }`. A command pattern
is a shell-like string used only to describe argv; Forge does not execute it
through a shell. Without a wildcard it matches exactly
(`command: "git pull"`). A final `*` matches zero or more trailing arguments
(`command: "git pull *"`). Compound shell syntax, redirects, and leading
environment assignments are outside this contract. Translators map those
meanings to Claude's `--tools`/`--allowedTools`, Codex sandbox/config
arguments, or an OpenAI-compatible function-tool loop.

**Where a declaration is enforced depends on who owns the tool loop.**
Claude and Codex are *service backends*: they run their own loop and own
their own permission layer, so Forge's contract ends at composing the
invocation — translate `allowed` into the native vocabulary, pass
`--permission-mode` only when the mode is specified, and stop. What the CLI
then does with those values (including ignoring them under its own
`defaultMode`) is that system's runtime. Forge does not inject a
per-tool-call judgment hook to override it: overlaying one splits the
execution boundary across two systems so neither is a whole authority, and
it makes Forge's declared boundary silently depend on files outside Forge
(`.claude/settings.json`, `.codex/config.toml`). For the OpenAI-compatible
loop Forge *is* the loop — it receives and executes the tool calls — so
there `allowed` is the execution boundary and Forge judges each argv itself.

`allowed` is the **only** capability axis — there is no deny list.
Prohibition is expressed by leaving a tool off the list. Where Forge owns
the loop, everything off the list is denied (fail-closed), and transparent
`env`/`command`/`exec` launchers are normalized to the delegated executable
before the same allow policy is applied — a launcher is notational
convenience, never a way in, because anything not on the allow-list (the
launcher included) is denied. Environment assignments riding a launcher
(`env PATH=… forge`) are rejected for the same reason bare leading
assignments are: they split the judged binary from the executed one. An
explicit allow pattern for the launcher itself (e.g. `command: "command -v
*"`) takes precedence over launcher normalization. A deny axis was
deliberately removed because argv patterns are necessarily incomplete
(flags can be reordered, launchers interposed), and the two axes fail in
opposite directions when a pattern misses: an unmatched allow pattern
denies (a safe inconvenience), while an unmatched deny pattern silently
permits (a hole). A boundary whose spelling gaps are holes cannot perform
the boundary role at this layer, so deny does not exist here.
Omitting/null `allowed` means the declaration is not made at all — the
backend/cwd native configuration stands; `allowed: []` explicitly requests
no tool. For the OpenAI-compatible loop there is no native layer underneath
— Forge assembles the tool surface itself — so "follow native" (nil)
collapses to the empty surface; only `bypass` produces an unrestricted loop.

**The allow-list is a per-session exposure bound, not a transitive
closure.** An allowed executable is granted with its full behavior —
`command: "forge *"` grants the whole forge client surface including
`workflow dispatch`, and `git *` includes git's own embedded launchers.
Closure over composition (what a dispatched workflow may in turn do) is
owned by the dispatch ACL, not by capability — the engine closes no
composition edge of its own. `allowed` is a requested exposure, not a
declaration that every listed tool is required for the task. A provider may
conservatively leave an unsupported positive tool unavailable and emit
`agent.translation_fallback`. The Agent capability does not infer every
transitive side effect: `files.write` names the provider's file-write
surface, while actual filesystem authority is also bounded by the
translated permission and sandbox configuration.

**How much of the declaration survives translation is provider-shaped, and
on one backend most of it does not survive at all.** Claude has a per-tool
exposure flag, so `allowed` becomes `--tools`/`--allowedTools` and a tool
left off the list does not exist in the session. The OpenAI-compatible loop
is assembled by Forge, so the list is exact. **Codex has no per-tool knob**:
the translator can only turn off web search and multi-agent, so
`files.read`, `files.write`, `command`, `mcp`, and `schedule` declarations
reach the process as nothing at all. On Codex the file and shell surface is
bounded by `sandbox_mode` (which `permission_mode` sets), not by `allowed`
— an agent declared `allowed: [files.read]` there can still write if its
sandbox permits it. This is an accepted limitation of the backend rather
than a gap Forge fills: Forge composes the invocation with the knobs the
CLI offers and does not overlay a private enforcement layer to simulate the
missing ones. Read a declaration as intent plus whatever the target CLI can
honor, and consult `permission_mode` for the actual bound on Codex.

Tool observation on a service backend comes from that backend's own stream
— Claude's `stream-json`, Codex's JSONL — recorded in chronological turn
order as `agent.tool` events counting toward the response's `tool_calls`.
Forge does not attach a second observation channel to double-count
attempts; a tool the backend omits from its stream is not observed, which
is a property of that surface rather than a gap for Forge to fill by
injecting a hook.

A zero Codex process exit is necessary but not sufficient for success. Its
JSONL must contain `thread.started` with an identifier, a completed
`agent_message`, and `turn.completed`, with no malformed lines. An
incomplete successful stream is a protocol fault and does not advance the
session turn.

There is no `output_format` field — it isn't a workflow-authoring surface.
Internally `ClaudeBackend` always requests `stream-json` regardless of tool
declarations and extracts plain text + tool events before either ever
reaches a step's output; a workflow only ever sees the text.

`permission_mode` is the approval-authority concept (nobody checks / policy
boundary only / a human checks) — `bypass`/`safe`/`restrict`. Omitted (nil)
means the flag is not passed at all, so the spawned process falls back to
its own cwd/backend configuration (for example `.claude/settings.json` or
`.codex/config.toml`). A translator uses the closest conservative native
default when an interface is absent and emits `agent.translation_fallback`;
it fails only when continuing would widen an explicit security boundary.
`permission_mode` and `allowed` are orthogonal axes that meet as an
intersection: the effective surface is `allowed` ∩
approvable-under-this-mode. `restrict` demands a human approver; a backend
with no approval channel has an empty approvable set, so the intersection
collapses to no tools (with a diagnostic) — the mode does not overwrite the
capability, the meet is simply empty. On a service backend the two axes
translate to two distinct native knobs (exposed set vs approval level), so
declaring them together is not contradictory and both are carried through.
Where Forge owns the loop they collapse onto one knob — `allowed` *is* the
execution boundary and `bypass` says to remove it — so that translator
rejects the pair rather than silently dropping either side.

A multi-turn LLM call is **several `agent` steps**: each is one user turn
in the one session, so a later turn sees everything earlier turns said —
including a regeneration inside a `loop`, which continues the *same*
dialogue rather than starting over. The invoke step's output is the last
child step's output unless an explicit `output` says otherwise. Child
outputs live in a sub-scope and do not leak to the parent.

`share_session: true` means "reuse an ambient session if one exists." On
that path this invoke does not launch a new agent, so its
model/tools/cwd/permission fields are fallback declarations used only when
no ambient session is present. `share_session` resolves at run time (bool
or null; null reads as false).

`timeout` (seconds) wraps the whole session subtree — however many turns it
runs, including any time child leaves spend waiting for slots. Expiry
throws `HostTimeout` (recoverable).

```yaml
- id: session
  invoke:
    model: claude
    body:
      - id: draft
        agent: "Turn X into a Block Kit JSON array."
      - id: checked
        shell: { command: [jq, -e, "."], stdin: { ref: draft } }
        rescue:
          - id: repair
            agent:
              format: "That was not valid JSON — ${why}. Fix it and answer again."
              with: { why: { ref: checked.stderr } }
          - id: rechecked
            shell: { command: [jq, -e, "."], stdin: { ref: repair } }
    result: { ref: checked }
```

Inside the rescue, `checked` is the failure payload (so the repair turn can
quote the validator's `stderr`); the retrying agent turn also continues the
same session, so it already remembers what it wrote. Note the invoke's
`output` references `checked`, not a step the rescue rebound: rescue
bindings do not leak — the rescue's **last step's output** becomes the
failed step's value, which is why the recheck runs last.

### `agent`

A single prompt turn against the ambient agent session — `invoke` opens the
session; an `agent` step outside one is an authoring error. Bare expression
— the prompt is the value:

```yaml
- id: draft
  agent: Summarize the day.            # literal
- id: retry
  agent: { format: "fix: ${e}", with: { e: { ref: v.stderr } } }
```

The step's output is the turn's response text. For the `claude` backend
each turn is one `--session-id`/`--resume` call; `codex` uses `codex exec`
/ `codex exec resume <thread-id>`; the OpenAI-compatible backend
accumulates turns as messages in Forge's own function-tool loop. An `agent`
step takes a pool slot for the duration of its turn.

### `dispatch`

Asks the daemon for an **isolated run** — a host act with its own lifetime,
ACL and slot, not a language call. `use` is the function call; this is
`Process.run`. Exactly one of `name` (catalog) or `spec` (inline) names the
target; the daemon settles inputs against the target's signature.

```yaml
- id: child
  dispatch:
    name: <registered-workflow>   # or spec: <inline-workflow-object>
    inputs:
      <child-input>: <Expression>
    timeout: <seconds>            # optional
```

An inline `spec` body lowers through the same loader at decode time — same
registry, same vocabulary, same validation — so a malformed inline target
fails the load, not the run.

The child runs under its own run id with principal `cli:<parent-workflow>`
(`<inline>` sigil for inline specs). Trace context is inherited. The
dispatch step's output is the child's declared `outputs` map (`{}` if none).
A failed child throws `ChildRunFailed` — recoverable.

`timeout` bounds the child run's *execution*: the timer starts when the
child first transitions to running (queue wait excluded, one level deep),
and on expiry the child's in-flight work is cancelled along with the
dispatch. Starvation has no queue-wait backstop — it is surfaced by
observation (`workflow.health`) and resolved by operator cancel, not by a
timer.

Safety:

- **cycle detect** — the same registered workflow name twice on the
  dispatch stack is rejected (inline specs are exempt: each instance is a
  distinct spec).
- **depth limit** — chains deeper than 8 are rejected.
- **policy gate** — the parent's `cli:<name>` principal must be allowed to
  call the child.

### `resource`

Asks the resource root one of two questions, named by what the step gets
back — exactly one of `content` or `path`.

**`content`** reads the file and renders it as a template over `inputs` — a
runtime value source. The body is a template surface (`${name}`
placeholders) closed over the given inputs; there is no include layer —
composition happens in the workflow (steps, `format`), not inside resource
files.

```yaml
- id: prompt
  resource:
    content: greeting.txt         # expression, relative to the resource root
    inputs: { name: { ref: who } }   # optional bindings
```

The output is the rendered string. Without `inputs`, the file must use no
placeholders (a placeholder naming an undeclared binding is an error, never
an ambient lookup).

**`path`** resolves the file's absolute location without reading it — the
form for handing a script to `shell`, where rendering would be wrong twice
over: a script's own `$` syntax is not template dialect, and an executable
wants to be run, not inlined. The file must exist; `inputs` are rejected
(a location does not render).

```yaml
- id: script
  resource: { path: script/cursor.sh }
- id: run
  shell: { command: [/bin/sh, { ref: script }, "--flag"] }
```

### `dynamic`

Steps that arrived **as data** — `compose` is a list of expressions, each
resolving to a step object or an array of them (typically carried through a
signature); the kernel's runtime lowering door turns them into IR through
the same decoder and registry the load path uses. No text is re-parsed.

```yaml
- id: run
  dynamic:
    compose:
      - { ref: steps }         # a batch from the caller
      - value: { id: tail, value: composed-ok }   # a literal step, quoted
    result: { ref: tail }             # optional
```

A literal step object must be **quoted** (`- value: { …step… }`) — an
unquoted record would be read as an expression and rejected for its
half-form keys.

The fragment is a **closed scope**: its references see only the fragment's
own step ids plus the `run`/`origin` contexts — never the ambient scope.
Caller values arrive embedded in the step data (evaluate them in the
caller's scope when composing), and a reference meant to resolve *inside*
the fragment is deferred one layer by quotation: `{ value: { ref: inner } }`
(quasiquote). The lowered fragment is validated before any of it runs.
`output` is authored in the enclosing spec, so it sees the ambient scope
plus the fragment's step results.

## Condition

Data-only. A predicate is exactly two keys — `of` names the subject, the
operator key carries the operand — and **both sides are full expressions**,
so a reference can compare against another reference, not only a literal.
The unary `present` takes its expression directly, without `of`.

```yaml
{ of: <expression>, is: <expression> }
{ of: <expression>, is_not: <expression> }
{ of: <expression>, one_of: <expression> }   # must resolve to an array
present: <expression>
all_of:  [ <Condition>, ... ]
any_of:  [ <Condition>, ... ]
not:     <Condition>
```

Library atoms (`contains`, `starts_with`, `regex`, host additions) take the
same binary shape: `{ of: <expression>, regex: "sp.c$" }`. An atom operand
that is inert data is validated at load; one that resolves at run time is
judged there.

`is` equality crosses `int`/`double` for numerically equal values. `one_of`
answers whether the subject matches any element of the operand array.

Absence keeps the kernel's policy when the subject is a plain `{ ref: }`:
`is` answers `false`, `is_not` answers `true`, `present` answers `false`,
and a shape-misusing drill (`unfit` — e.g. asking a field of an int) throws
instead of reading as `false`. Any other subject shape is a full expression
and resolves strictly. The composite keys (`is_not`/`one_of`/`all_of`/
`any_of`) are **snake_case** here — distinct from the input signature's
`oneOf`, which is camelCase.

## OutputSpec — `shell.outputs` extractors

Only `shell` decomposes its stdout; every other action speaks structured
values already. Shorthand (bare JSONPath):

```yaml
name: $.user.name
```

Full form:

```yaml
count:
  path: $.total
  type: int
  default: 0
  hint: total items
```

Exactly one extractor:

| Field | Notes |
|-------|-------|
| `path` | JSONPath subset (`$`, `$.field`, `$.a.b`, `$.arr[0]`, `$.arr[-1]`, `$.arr[*]`, `$.obj.*`) |
| `regex` | first capture group; multi-line OK |
| `line` | 0-indexed (negative counts from end) |

Modifiers:

| Field | Notes |
|-------|-------|
| `type` | `string` (default) / `int` / `float` / `bool` / `json` — coerced |
| `default` | fallback value when missing. No separate `required` field — a declared `default` (even `null`) means a missing path doesn't fail the step; leaving `default` out makes the path mandatory (missing → `OutputResolutionError`) |
| `hint` | human description |

## Top-level `outputs`

Each output is an expression, resolved in the final scope:

```yaml
result:
  summary: { ref: search.summary }
  banner: { format: "run ${id}", with: { id: { ref: run.workflow_id } } }
```

A workflow's `outputs` map is its public contract — what callers see in the
dispatch result. A workflow with no `outputs` declared returns an empty
object; its caller cannot observe internal state.

## Expression — the value language

Five shapes, all pure data (no frontend may hide an expression inside a
string, so any FE that can spell an object can spell every expression):

| Form | Example | Meaning |
|------|---------|---------|
| Scalar literal | `plain text`, `42`, `true`, `null` | itself — a string is **always** literal text, never parsed |
| Reference | `{ ref: items[0].name }` | resolve the path in the consuming scope |
| Quotation | `{ value: <data> }` | the payload verbatim, never evaluated — also the escape for data that looks like a form |
| Format | `{ format: "hi ${who}", with: { who: { ref: who } } }` | closed interpolation — the template sees only its declared bindings |
| Record / array | `{ <key>: <expr>, ... }`, `[ <expr>, ... ]` | elements are expressions |

A record carrying `ref` / `value` / `format` / `with` keys must be exactly
one of the forms above — anything half-spelled is rejected at load with a
pointer to `{ value: }`. An ordinary record without those keys is just a
record of expressions.

The template dialect (`${path}` placeholders, `$$` for a literal `$`,
`[i]`/`[${i}]` index references) lives on exactly two closed surfaces:
`format` template strings and resource file bodies. Both render against
their declared bindings only — a placeholder naming anything undeclared is
a load error, never an ambient lookup. Everywhere else `${` is inert text
(`forge workflow check` flags it as a likely stale-grammar mistake; quote
with `{ value: }` when it is genuinely meant verbatim).

## Scope at evaluation time

When a step's expressions are resolved, the scope contains:

- `inputs.<key>` — workflow inputs filled with defaults / `null` for missing optionals
- `<step-id>` — the output of a completed previous step (fields via `<id>.<key>`)
- `origin.kind` / `origin.id` — what dispatched this run (manual/rpc/schedule/workflow)
- `run.workflow_id` — this run's id · `run.root_id` — the node-tree root id
  (`== workflow_id` for a top-level run). Both are log-grep keys.

Sub-scopes (`group` / branch arms / `loop` and `each` bodies / `invoke`
steps) may reuse an outer step id — the retry-loop idiom rebinds the outer
id on purpose; only same-level duplicates are ambiguous. Parallel children
bind under their parent (`{ ref: par.child }`) — child ids are not merged
into the enclosing scope. `dynamic` fragments are closed (see the action).

## Validation

The validator (run by the daemon at load time and by `forge workflow check`
on demand) catches:

- unknown keys anywhere in the grammar, and half-spelled expression forms
- `{ ref: X }` with undeclared X, and refs to invisible step ids —
  on **both sides** of a condition predicate
- format templates naming a binding not declared in `with`
- duplicate sibling step ids, reserved-head collisions, empty `rescue`
  (inside a rescue, the failed step's own id is legitimately visible — it
  names the failure payload)
- a `default` that does not fit its own `type`/`oneOf`
- a literal atom operand its atom rejects (e.g. an invalid `regex` pattern)

It does NOT catch (intentional limit — keeps the validator local and the
store simple):

- `{ ref: step.X.Y }` field-level refs against runtime value shape
- cross-workflow refs (dispatch child outputs)

Use `forge workflow check` for the same shallow checks without a daemon.
Use external tooling (e.g. dispatch with sample inputs) for the deeper
checks.
