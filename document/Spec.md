# Workflow Spec

Reference for the workflow YAML format. Companion to `API.md` (which covers the
RPC/CLI surface). The language is [Warp](https://github.com/wlsdms0122/Warp) —
its notation lives in `WarpIR`, and forge adds six verbs of its own in
`package/Sources/Forge/Service/Workflow/Warp`. Those decoders are the live
source of truth; this document tracks them.

- [Document — the module](#document--the-module)
- [Procedure — the callable unit](#procedure--the-callable-unit) · [Parameter](#parameter)
- [Statement — the execution unit](#statement--the-execution-unit)
- [Constructs](#constructs) — [`value`](#value) · [`group`](#group) · [`branch`](#branch) · [`loop`](#loop) · [`each`](#each) · [`parallel`](#parallel) · [`attempt`](#attempt) · [`call`](#call) · [`abort`](#abort)
- [forge verbs](#forge-verbs) — [`shell`](#shell) · [`invoke`](#invoke) · [`agent`](#agent) · [`dispatch`](#dispatch) · [`resource`](#resource) · [`dynamic`](#dynamic)
- [Failure and recovery](#failure-and-recovery)
- [Condition](#condition)
- [Standard vocabulary](#standard-vocabulary)
- [OutputSpec — `shell.outputs` extractors](#outputspec--shelloutputs-extractors)
- [Expression — the value language](#expression--the-value-language)
- [Scope at evaluation time](#scope-at-evaluation-time)
- [Validation](#validation)

Workflow files are YAML (`*.yaml`), decoded with Yams. YAML comments (`#`) are
allowed, and multiline strings can be written with block scalars (`|`). (The
inline `--spec` passed over IPC/CLI stays a JSON object — that wire format is
unchanged; only the on-disk file format is YAML.)

> **Scalar typing — YAML notation, JSON semantics.** Untyped value positions
> (parameter `default`s, `arguments:` maps, condition operands, record/array
> literals) are typed by **JSON literal rules**, not YAML 1.1 resolution:
> only lowercase `true`/`false`, `null`/`~`/empty, and JSON-shaped numbers
> (no leading zeros) are typed — everything else is a string. So unquoted
> `no`, `on`, `09:20`, `007`, `1.10.2` are all **strings**; no quoting
> needed. Any quoted or block scalar is always a string, even `"true"`.
> A whole number too wide for a 64-bit int is refused rather than silently
> becoming a float — quote it if the text was meant as a string.
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

## Document — the module

A workflow file is a **module**: metadata plus the procedures it declares.
There is no top level to run — a file that declared its body at the root would
be an entry point and nothing else, leaving no way to write a file that only
declares.

```yaml
name: <workflow-name>       # must equal the file basename
description: ...            # optional
types:                      # optional — named types, visible across the link
  <TypeName>: <Type>
const:                      # optional — names bound to values at load
  <key>: <Expression>
procedures:                 # required, non-empty
  <procedure-name>: <Procedure>
```

Required: `procedures`, and it must declare at least one. A module that
declares nothing can never be linked into anything.

**One procedure per file, named after the file.** The language lets a module
declare many; forge's catalog does not. A file named `deploy.yaml` declares
`procedures: { deploy: ... }` and nothing else — a file declaring two, or one
under a different name, is refused with a `procedure/filename mismatch` and
excluded from the catalog. That is what makes a workflow one thing you can run
by the name you know it by: the daemon links every workflow it can see and
starts from that one symbol.

To reach another workflow's procedure, [`call`](#call) it by name — the whole
catalog is in the link.

`name` is metadata: identity comes from the store key (the file basename), never
from the body. Inline anonymous specs (`workflow.dispatch --spec` or a
`dispatch` step's `spec`) carry no `name`, are one procedure's worth of data
rather than a document, and are stamped `<inline>` by the daemon.

`types:` declares names a parameter or `answers:` may then use. A type name
declared twice across the link is a link error.

`const:` binds a name to a value at load. Constants are settled once, before
anything runs, and a constant is not a step — it cannot read a parameter or a
step result.

There is no whole-workflow `timeout` field. Deadlines are per action —
`shell`, `invoke`, and `dispatch` each take a `timeout` (seconds); see those
verbs. Runaway protection beyond that (observation, cancellation) is the
operator's surface (`workflow.health`, `workflow.cancel`), not a spec field.

## Procedure — the callable unit

```yaml
<procedure-name>:
  description: ...          # optional
  parameters:               # optional
    <key>: <Parameter>
  receiver: <parameter>     # optional — which parameter this is sent to
  answers: <Type>           # optional — what it answers, defaults to `any`
  body:                     # optional
    - <Statement>
  result: <Expression>      # optional
```

Absent `parameters:` means an **empty signature**, not an absent contract — a
procedure that declares nothing takes nothing, so a stray caller input is
rejected instead of leaking into scope.

`result:` is **one expression**, because a procedure answers one value. Several
named answers are a record, which is a thing the author writes:

```yaml
result:
  summary: { ref: search.summary }
  banner: { format: "run ${id}", with: { id: { ref: run.workflow_id } } }
```

A procedure with no `result:` answers with its last statement, the way a block
does. A procedure with no `body:` is one that only answers.

`receiver:` names one of its own parameters as the thing the procedure is sent
*to*, which is what makes it reachable as `${x.word}` and as a condition
operator. See [Standard vocabulary](#standard-vocabulary).

A workflow's `result:` is its public contract — what callers see in the dispatch
result. A workflow with no `result:` answers `null`; its caller cannot observe
internal state.

### Parameter

Shorthand (bare type — anything a type can be spelled as):

```yaml
workspace: string
tags: array<string>
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
| `type` | `string` / `int` / `double` / `bool` / `object` / `array` / `procedure` / `any`, `array<T>` / `object<T>`, a name from `types:`, a record `{ id: string }`, or `{ procedure: { parameters:, answers: } }` | required. **Enforced at the scope boundary**: a value whose type mismatches is rejected with `InputValidationError` before any step runs. Numeric values normalize to the declared representation — an integral double settles as `int`, an int settles as `double`. |
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

A declaration's own `default` passes the same gate a caller's value would, and
what is stored is the settled result — a default-supplied slot never reads a
different type than a caller-supplied one.

Parameters **settle once** at the scope boundary: inside, references read the
settled values instead of re-evaluating, and only declared names exist. A
parameter is read by its bare name — `{ ref: channel }`, not `inputs.channel`.

## Statement — the execution unit

```yaml
- id: search              # or `var:` or `set:` — exactly one
  <construct>: <...>      # exactly one construct key
```

A statement is a **name plus exactly one construct key**. The envelope carries
no modifiers — there is no `when:` to gate a statement and no `rescue:` to
guard it, because no language spells them that way. `some() when x > 0` is not
a form anyone writes; `if x > 0 { some() }` is, and that is
[`branch`](#branch). Recovery is [`attempt`](#attempt), which guards a body
rather than one statement. Zero or two construct keys on one statement is a
load error.

How the name is spelled is what the statement does to it:

| Spelling | Meaning |
|----------|---------|
| `id:` | fixes a name — it may not be written again at this level |
| `var:` | introduces a name that may be written again |
| `set:` | writes a name a `var:` declared earlier |

```yaml
- var: attempts
  value: 0
- id: gate
  loop:
    where: { of: { ref: attempts }, lessThan: 3 }
    body:
    - set: attempts
      call: { procedure: plus, arguments: { of: { ref: attempts }, value: 1 } }
```

A `var:` written inside a sub-scope belongs to that scope. To carry a value out
of a loop or a branch, declare it with `var:` outside and `set:` it inside — the
outer binding keeps the last value written.

## Constructs

### `value`

The identity construct — the statement's value is the expression's value.

```yaml
- id: greet
  value: { format: "hello, ${name}", with: { name: { ref: who } } }
```

### `group`

A named sub-scope: statements run in sequence and the group answers with one
value — the explicit `result` expression (resolved in the group's scope) or,
absent that, the last statement's value. Names bound inside live in the
sub-scope and do not leak to the parent.

```yaml
- id: blk
  group:
    body: [ <Statement>, ... ]
    result: <Expression>   # optional
```

### `branch`

Conditional then/else.

```yaml
- id: pick
  branch:
    when: <Condition>
    then:
      body: [ <Statement>, ... ]
      result: <Expression>  # optional
    else:                   # optional
      body: [ <Statement>, ... ]
      result: <Expression>
```

Each arm is a sub-scope like `group`. The taken arm's `result` (or `null`
without one) becomes the branch's value; a false condition with no `else`
answers `null`.

### `loop`

Repeat `body` **while `where` holds** — a `while` loop, not a retry primitive.
Each round binds `<statement-id>.index` (0-based) before evaluating `where`, so
the condition and the body can read the round counter.

```yaml
- id: gate
  loop:
    where: { of: { ref: "gate.index" }, is_not: 2 }
    body: [ <Statement>, ... ]
    guard: 5                # optional iteration budget
    result: { ref: latest }  # optional, resolved when the loop ends
```

- When `where` first answers false, the loop ends and `result` (resolved in
  the final round's scope) becomes the value — `null` without one. If `where`
  is false immediately, the body runs zero times.
- `guard` is an optional positive iteration budget. Exceeding it throws
  `LoopGuardExceeded` — recoverable, so an `attempt` can express "gave up but
  continue." Without `guard` the language does not prevent an author's
  infinite loop, any more than Swift does; deadlines and observation are the
  caller's concern.
- Iterating over material the workflow already holds is [`each`](#each), whose
  structure guarantees termination without a budget.

**Visibility is two-layered**, and the layers answer different questions:

- *Load time* — `where` and the body are validated against the scope
  **outside** the loop: names declared before the loop, plus
  `<statement-id>.index`. A body statement's id is not visible to `where` at
  load time; to be readable there, the name must already exist outside.
- *Run time* — the loop keeps one frame across rounds. When the body writes a
  name the frame already holds (a `set:` on a `var:` declared outside), the
  next round's `where` — and the next round's body — see the new value. When
  the loop ends the frame is discarded; the outer binding keeps the last
  value written.

Together these produce the validate-and-retry idiom: **declare the name with
`var:` outside, run the first check into it, and have the body `set:` it**:

```yaml
- var: verdict                # declared outside — visible to `where`
  attempt:
    body:
    - id: first
      shell: { command: [jq, -e, "."], stdin: { ref: draft } }
    result: { ref: first }
    rescue:
      result: { format: "RETRY: ${why}", with: { why: { ref: verdict.stderr } } }
- id: gate
  loop:
    where: { of: { ref: verdict }, startsWith: "RETRY: " }
    guard: 3
    body:
    - id: fix
      agent: { format: "invalid — ${e}. fix it.", with: { e: { ref: verdict } } }
    - set: verdict            # the next round's `where` sees this
      attempt:
        body:
        - id: rechecked
          shell: { command: [jq, -e, "."], stdin: { ref: fix } }
        result: { ref: rechecked }
        rescue:
          result: { format: "RETRY: ${why}", with: { why: { ref: verdict.stderr } } }
    result: { ref: verdict }
```

Inside an [`invoke`](#invoke) session the regenerating `agent` turn **continues
the same LLM session** (it does not re-send the prior output; the session
remembers it).

### `each`

One round per element of `in` — `loop`'s structurally-terminating sibling. Each
round binds `<statement-id>.item` and `<statement-id>.index`; with `result`, the
per-round values collect into an array (without it, `null`).

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

`in` resolving to a non-array is `ReferenceUnfit` (shape misuse), not an empty
iteration.

### `parallel`

Running things at once, in the two shapes a fan-out comes in. Exactly one of
`do` or `in` — they are different questions.

**`do`** fans out over work the document wrote, and answers a record keyed by
the children's ids:

```yaml
- id: par
  parallel:
    do:
    - id: left
      value: 1
    - id: right
      value: 2
    completion: all         # optional — `all` (default) or `any`
```

Child ids must be distinct and the list non-empty. Read a child with
`{ ref: par.left }` — children bind under their parent, not into the enclosing
scope.

**`in`** fans out over a collection, borrowing `each`'s words on purpose — same
material, same body, same element — and answers an array in the collection's
order:

```yaml
- id: fetched
  parallel:
    in: { ref: urls }
    body:
    - id: got
      shell: { command: [curl, -sS, { ref: fetched.item }] }
    result: { ref: got }
```

Each piece runs against a **copy** of the enclosing scope, so siblings cannot
see one another and nothing a piece binds survives it.

`completion` says when the fan-out is finished:

- **`all`** (default) — every piece runs to the end. If any failed, the step
  fails with `ParallelFailed`, which is recoverable only when every failed
  piece failed recoverably: one author mistake makes the whole step an author
  mistake, because a rescue must not absorb a typo just because a sibling
  happened to time out.
- **`any`** — the first piece to succeed wins, and the rest are asked to stop.
  The value is the winner's alone; which piece won is not reported, so a piece
  that needs to say which one it was says so in what it answers. If every piece
  fails, `any` fails the way `all` does.

The language sets no cap on how wide a fan-out may be. Bounding it is the
program's business, and forge's own bound is the step-slot pool
(`maximum_concurrent_steps`), which `shell` and `agent` acquire.

### `attempt`

do-catch, written where the author wants it. What it guards is a **body**,
which is the shape Swift's own do-catch has and the shape an envelope key could
never express.

```yaml
- id: caught
  attempt:
    body: [ <Statement>, ... ]
    result: <Expression>    # optional
    rescue:
      body: [ <Statement>, ... ]
      result: <Expression>
```

If the guarded body fails **recoverably**, the rescue block runs and its value
becomes the attempt's value. An empty `rescue` is rejected at load: it would
swallow a failure into `null` without a trace — if the alternate path produces
nothing, the honest form is no attempt at all.

**While the rescue runs, the failure is a value** bound under the attempt's own
id, so the rescue can read what went wrong — `{ ref: caught.message }`, a shell
failure's `{ ref: caught.stderr }`. The moment the rescue answers, the id is
rebound to the rescue's value, so the payload never leaks past it. See
[Failure and recovery](#failure-and-recovery) for the payload shapes.

### `call`

Call a procedure **by name**, against its signature.

```yaml
- id: sub
  call:
    procedure: child
    arguments:
      who: { ref: who }
```

`procedure:` names a symbol, never a document — which module declared it is the
linker's business. A bare name resolves to the declaration that answers to it;
qualify with `<module>.<name>` when more than one does. Arguments settle at the
callee's boundary, and the callee's `result` comes back as this statement's
value.

`call` is the function call; [`dispatch`](#dispatch) is `Process.run`.

> A construct key rather than a bare word (`child: { who: ... }`) because a
> statement's construct key is read at decode time, and a procedure's name is
> not known until the link. A name known only after linking cannot be a
> statement key.

### `abort`

The language's `throw` — end here with a reason (the expression is the message).
Recoverable: an enclosing `attempt`, or a caller that treats the failure, may
absorb it; unhandled, the run fails with the message.

```yaml
- id: stop
  abort: { format: "unsupported kind: ${k}", with: { k: { ref: kind } } }
```

> **`invoke` means forge's verb here.** Warp spells "call a value that is a
> procedure" `invoke:` too, and forge has spent that word on an agent session
> since before the language had one. forge takes the word back in its own
> registry, so the language's `invoke` is not available in a workflow file. A
> procedure held as a value is reached through a word that takes it as an
> argument.

## forge verbs

These are declarations like any other — a module named `forge` in every link.
Their names are ordinary, so a workflow that declares its own `agent` procedure
shadows nothing: the verb is reached as `forge.agent`, and the construct key
below is the spelling that gets you there.

### `shell`

```yaml
- id: build
  shell:
    command: [swift, build, --package-path, package]  # array of expressions
    cwd: <Expression>                 # optional
    env: { <key>: <Expression> }      # optional
    stdin: <Expression>               # optional
    outputs: { <key>: <OutputSpec> }  # optional stdout extractors
    timeout: <seconds>                # optional deadline
```

`command` is an argv array (never a single shell string — nothing is
re-parsed through a shell). Element `[0]` is the executable. A nonzero exit
throws `BackendNonzeroExit` carrying `{exit_code, stderr, stdout}` —
recoverable. On success the value is the stdout decomposed by `outputs`
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

`shell` and `agent` are the slot-taking verbs: each acquires a slot from the
global pool (`maximum_concurrent_steps`) for the duration of its work.
`timeout` bounds the work itself; expiry throws `DeadlineExceeded`
(recoverable).

### `invoke`

The agent **session envelope** — not a plain group. It resolves the session
settings at its boundary, opens the ambient session, and runs its body inside;
`agent` steps only make sense in here.

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
    body: [ <Statement>, ... ]  # agent turns and anything between them
    result: <Expression>        # optional; default = last statement's value
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
reaches a statement's value; a workflow only ever sees the text.

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

A multi-turn LLM call is **several `agent` statements**: each is one user turn
in the one session, so a later turn sees everything earlier turns said —
including a regeneration inside a `loop`, which continues the *same* dialogue
rather than starting over. The invoke's value is the last statement's value
unless an explicit `result` says otherwise. Names bound inside live in a
sub-scope and do not leak to the parent.

`share_session: true` means "reuse an ambient session if one exists." On
that path this invoke does not launch a new agent, so its
model/tools/cwd/permission fields are fallback declarations used only when
no ambient session is present. `share_session` resolves at run time (bool
or null; null reads as false).

`timeout` (seconds) wraps the whole session subtree — however many turns it
runs, including any time nested work spends waiting for slots. Expiry throws
`DeadlineExceeded` (recoverable).

A fan-out **severs the ambient session**: pieces of a `parallel` must not share
one conversation, so a piece that needs a session opens its own `invoke` inside
itself.

```yaml
- id: session
  invoke:
    model: claude
    body:
      - id: draft
        agent: "Turn X into a Block Kit JSON array."
      - id: checked
        attempt:
          body:
            - id: first
              shell: { command: [jq, -e, "."], stdin: { ref: draft } }
          result: { ref: first }
          rescue:
            body:
              - id: repair
                agent:
                  format: "That was not valid JSON — ${why}. Fix it and answer again."
                  with: { why: { ref: checked.stderr } }
              - id: rechecked
                shell: { command: [jq, -e, "."], stdin: { ref: repair } }
            result: { ref: rechecked }
    result: { ref: checked }
```

Inside the rescue, `checked` is the failure payload (so the repair turn can
quote the validator's `stderr`); the retrying agent turn also continues the
same session, so it already remembers what it wrote.

### `agent`

A single prompt turn against the ambient agent session — `invoke` opens the
session; an `agent` statement outside one is an authoring error. Bare
expression — the prompt is the value:

```yaml
- id: draft
  agent: Summarize the day.            # literal
- id: retry
  agent: { format: "fix: ${e}", with: { e: { ref: v.stderr } } }
```

The value is the turn's response text. For the `claude` backend each turn is
one `--session-id`/`--resume` call; `codex` uses `codex exec` / `codex exec
resume <thread-id>`; the OpenAI-compatible backend accumulates turns as
messages in Forge's own function-tool loop. An `agent` statement takes a pool
slot for the duration of its turn.

### `dispatch`

Asks the daemon for an **isolated run** — an effect with its own lifetime, ACL
and slot, not a language call. [`call`](#call) is the function call; this is
`Process.run`. Exactly one of `name` (catalog) or `spec` (inline) names the
target; the daemon settles inputs against the target's signature.

```yaml
- id: child
  dispatch:
    name: <registered-workflow>   # or spec: <inline-workflow-object>
    inputs:
      <child-parameter>: <Expression>
    timeout: <seconds>            # optional
```

An inline `spec` is one procedure's worth of data (not a document with
`procedures:`), and it lowers through the same loader at decode time — same
registry, same vocabulary, same validation — so a malformed inline target fails
the load, not the run.

The child runs under its own run id with principal `cli:<parent-workflow>`
(`<inline>` sigil for inline specs). Trace context is inherited. The
dispatch's value is the child's `result` (`null` if it declares none). A
failed child throws `ChildRunFailed` — recoverable.

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

Asks the resource root one of two questions, named by what the statement gets
back — exactly one of `content` or `path`.

**`content`** reads the file and renders it as a template over `inputs` — a
runtime value source. The body is a template surface (`${name}`
placeholders) closed over the given inputs; there is no include layer —
composition happens in the workflow (statements, `format`), not inside resource
files.

```yaml
- id: prompt
  resource:
    content: greeting.txt            # expression, relative to the resource root
    inputs: { name: { ref: who } }   # optional bindings
```

The value is the rendered string. Without `inputs`, the file must use no
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

Statements that arrived **as data** — `compose` is a list of expressions, each
resolving to a statement object or an array of them (typically carried through
a signature); the language's runtime lowering door turns them into IR through
the same decoder and registry the load path uses. No text is re-parsed.

```yaml
- id: run
  dynamic:
    compose:
      - { ref: steps }                            # a batch from the caller
      - value: { id: tail, value: composed-ok }   # a literal statement, quoted
    result: { ref: tail }                         # optional
```

A literal statement object must be **quoted** (`- value: { …statement… }`) — an
unquoted record would be read as an expression and rejected for its half-form
keys.

The fragment is a **closed scope**: its references see only the fragment's own
ids plus the `run`/`origin` names — never the ambient scope. Caller values
arrive embedded in the statement data (evaluate them in the caller's scope when
composing), and a reference meant to resolve *inside* the fragment is deferred
one layer by quotation: `{ value: { ref: inner } }` (quasiquote). The lowered
fragment is validated before any of it runs. `result` is authored in the
enclosing procedure, so it sees the ambient scope plus the fragment's results.

A lowered statement may not take one of the ambient names (`origin`, `run`) as
its own id.

## Failure and recovery

What [`attempt`](#attempt) may absorb is exactly the **recoverable** class —
failures whose cause lies in the executed content or the outside world:

- `abort` (the author's own thrown reason)
- a reference whose upstream never produced the value (`ReferenceNotFound`)
- a nonzero shell exit (`BackendNonzeroExit`)
- a failed child run from `dispatch` (`ChildRunFailed`)
- an exhausted loop budget (`LoopGuardExceeded`)
- a `parallel` whose failed pieces all failed recoverably (`ParallelFailed`)
- an expired deadline (`DeadlineExceeded`)

Every payload carries `type` and `message`; each failure adds its own fields:

| `type` | extra fields |
|--------|--------------|
| `aborted` | — |
| `reference_not_found` | `path` |
| `loop_guard_exceeded` | `limit` |
| `parallel_failed` | `failures` (piece name → reason) |
| `nonzero_exit` | `exit_code`, `stderr`, `stdout` |
| `child_run_failed` | — |
| `timeout` | `seconds` |

Author mistakes and engine faults — shape misuse (`ReferenceUnfit`),
contract violations, misconfiguration, unclassified exceptions — are never
absorbed and propagate loud. **Cancellation** is an instruction, not an
outcome: a rescue never runs for a cancelled statement.

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

Everything else is a **word being sent to the subject**:
`{ of: x, startsWith: "a" }` is `x` receiving `startsWith`. Which words exist
is not this notation's business — it is whatever the link declares, so
[standard words](#standard-vocabulary) and a workflow's own procedures are
reachable the same way. The operand lands under the parameter named `value`,
so a procedure meant to be spelled as an operator declares its operand that
way; one that does not is still reachable as a statement, where arguments are
written by name.

`is` equality crosses `int`/`double` for numerically equal values. `one_of`
answers whether the subject matches any element of the operand array.

Absence keeps the language's policy when the subject is a plain `{ ref: }`:
`is` answers `false`, `is_not` answers `true`, `present` answers `false`,
and a shape-misusing drill (`unfit` — e.g. asking a field of an int) throws
instead of reading as `false`. Any other subject shape is a full expression
and resolves strictly.

The grammar's own keys (`is_not` / `one_of` / `all_of` / `any_of` / `not` /
`present` / `of`) are **snake_case** and reserved — distinct from the parameter
signature's `oneOf`, which is camelCase, and from the standard words, which are
camelCase because they are ordinary declarations rather than grammar.

## Standard vocabulary

`std` is a module in every link, so its words are declarations like any other.
Each takes its subject as `of` and its operand as `value`, which is what makes
it spellable as a condition operator and as `${x.word}`.

| Word | Subject | Answers |
|------|---------|---------|
| `count` | any | how many |
| `contains` | string / array | whether it holds `value` |
| `startsWith` | string | whether it begins with `value` |
| `regex` | string | whether it matches the pattern `value` |
| `plus` `minus` `times` `dividedBy` | number | the arithmetic |
| `lessThan` `greaterThan` | number | the comparison |
| `uppercased` `lowercased` `trimmed` | string | the text |
| `first` `last` `reversed` | array | the element / the array |
| `split` | string | cut on `value` |
| `joined` | array of strings | written one after another, `value` between |
| `replacing` | string | every `value` swapped for `with` |

A word is reached three ways, and **only one of them is the `{ of:, <word>: }`
shape**:

```yaml
# 1. as a condition operator — `where:` and `when:` read the condition grammar
- id: pick
  branch:
    when: { of: { ref: name }, startsWith: "wf-" }

# 2. through a reference path, for a word that needs no operand
- id: n
  value: { ref: items.count }

# 3. as a call, which is the general form
- id: n
  call: { procedure: count, arguments: { of: { ref: items } } }
- id: bumped
  call: { procedure: plus, arguments: { of: { ref: n }, value: 1 } }
```

> **The condition shape is not an expression.** `{ of: x, count: {} }` written
> where a *value* is wanted is an ordinary record with two fields — the operator
> grammar lives in `when:`/`where:` and nowhere else. Nothing rejects it,
> because a record of two fields is a legal value, so this is a silent wrong
> answer rather than a load error. In value position, use a reference path or
> `call:`.

## OutputSpec — `shell.outputs` extractors

Only `shell` decomposes its stdout; every other verb speaks structured values
already. Shorthand (bare JSONPath):

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
| `default` | fallback value when missing. No separate `required` field — a declared `default` (even `null`) means a missing path doesn't fail the statement; leaving `default` out makes the path mandatory (missing → `OutputResolutionError`) |
| `hint` | human description |

## Expression — the value language

Six shapes, all pure data (no front end may hide an expression inside a string,
so any notation that can spell an object can spell every expression):

| Form | Example | Meaning |
|------|---------|---------|
| Scalar literal | `plain text`, `42`, `true`, `null` | itself — a string is **always** literal text, never parsed |
| Reference | `{ ref: items[0].name }` | resolve the path in the consuming scope |
| Quotation | `{ value: <data> }` | the payload verbatim, never evaluated — also the escape for data that looks like a form |
| Format | `{ format: "hi ${who}", with: { who: { ref: who } } }` | closed interpolation — the template sees only its declared bindings |
| Closure | `{ closure: { parameters: {...}, body: [...], result: ... } }` | a procedure written where a value is wanted |
| Record / array | `{ <key>: <expr>, ... }`, `[ <expr>, ... ]` | elements are expressions |

A record carrying `ref` / `value` / `format` / `with` / `closure` keys must be
exactly one of the forms above — anything half-spelled is rejected at load with
a pointer to `{ value: }`. An ordinary record without those keys is just a
record of expressions. That set is **fixed**, unlike the construct keys, because
it is the quoting boundary: widening it would turn records that were data into
forms.

The template dialect (`${path}` placeholders, `$$` for a literal `$`,
`[i]`/`[${i}]` index references) lives on exactly two closed surfaces:
`format` template strings and resource file bodies. Both render against
their declared bindings only — a placeholder naming anything undeclared is
a load error, never an ambient lookup. Everywhere else `${` is inert text
(`forge workflow check` flags it as a likely stale-grammar mistake; quote
with `{ value: }` when it is genuinely meant verbatim).

## Scope at evaluation time

When a statement's expressions are resolved, the scope contains:

- `<parameter>` — the procedure's own parameters, settled, by bare name
- `<statement-id>` — the value of a completed earlier statement (fields via
  `<id>.<key>`)
- `<const>` — any name the module declared under `const:`
- `origin.kind` / `origin.id` — what dispatched this run (manual/rpc/schedule/workflow)
- `run.workflow_id` — this run's id · `run.root_id` — the node-tree root id
  (`== workflow_id` for a top-level run). Both are log-grep keys.

`origin` and `run` are supplied by the daemon and declared like everything
else: every procedure a workflow file declares gets them as parameters with a
default, so a workflow that never mentions them is still a workflow and one
that does is reading a name it can see. A statement may not take either name as
its own id.

Sub-scopes (`group` / branch arms / `loop` and `each` bodies / `attempt` /
`invoke` bodies) are their own frames — a name bound inside does not leak out,
and writing an outer name takes `var:` outside and `set:` inside. `parallel`
children bind under their parent (`{ ref: par.child }`). `dynamic` fragments are
closed (see the verb).

## A complete workflow

Every construct in one shallow pass. This document is loaded, linked and run by
`DocumentTests` — the `runnable` tag on the block is what puts it there, so an
example added with that tag is checked and one without it is not.

```yaml runnable
name: tour
procedures:
  tour:
    description: One shallow pass over the language.
    parameters:
      who:
        type: string
        default: world
      mode:
        type: string
        oneOf: [a, b]
        default: a
      items:
        type: array<string>
        default: [one, two]
    body:
    - id: greet
      value: { format: "hello, ${name}", with: { name: { ref: who } } }
    - id: quoted
      value: { value: { ref: kept-as-data } }
    - id: size
      value: { ref: items.count }
    - id: pick
      branch:
        when: { of: { ref: mode }, is: a }
        then:
          body:
          - id: chosen
            value: took-a
          result: { ref: chosen }
        else:
          result: took-b
    - var: rounds
      value: 0
    - id: gate
      loop:
        where: { of: { ref: rounds }, lessThan: 2 }
        guard: 5
        body:
        - set: rounds
          call: { procedure: plus, arguments: { of: { ref: rounds }, value: 1 } }
        result: { ref: rounds }
    - id: walk
      each:
        in: { ref: items }
        body:
        - id: tagged
          value:
            format: "${index}:${item}"
            with:
              index: { ref: walk.index }
              item: { ref: walk.item }
        result: { ref: tagged }
    - id: par
      parallel:
        do:
        - id: left
          value: 1
        - id: right
          value: 2
    - id: race
      parallel:
        completion: any
        do:
        - id: fine
          value: winner
        - id: doomed
          abort: not this one
    - id: mapped
      parallel:
        in: { ref: items }
        body:
        - id: shouted
          value: { ref: mapped.item.uppercased }
        result: { ref: shouted }
    - id: blk
      group:
        body:
        - id: inner
          value: grouped
        result: { ref: inner }
    - id: caught
      attempt:
        body:
        - id: bailing
          abort: bail out
        rescue:
          result: { format: "rescued: ${why}", with: { why: { ref: caught.message } } }
    - id: called
      call:
        procedure: replacing
        arguments:
          of: { ref: greet }
          value: world
          with: { ref: mode }
    result:
      greeting: { ref: greet }
      quoted: { ref: quoted }
      size: { ref: size }
      branch: { ref: pick }
      loop: { ref: gate }
      walk: { ref: walk }
      parallel: { ref: par }
      race: { ref: race }
      mapped: { ref: mapped }
      group: { ref: blk }
      rescued: { ref: caught }
      called: { ref: called }
```

## Validation

The validator (run by the daemon at load time and by `forge workflow check`
on demand) catches:

- unknown keys anywhere in the grammar, and half-spelled expression forms
- `{ ref: X }` with undeclared X, and refs to invisible ids — on **both
  sides** of a condition predicate
- format templates naming a binding not declared in `with`
- duplicate sibling ids, reserved-name collisions, an empty `attempt` rescue
  (inside a rescue, the attempt's own id is legitimately visible — it names
  the failure payload)
- a `default` that does not fit its own `type`/`oneOf`
- a literal atom operand its word rejects (e.g. an invalid `regex` pattern)
- a call whose arguments do not fit the callee's signature, and a name no
  module in the link declares — these are the **linker's**, so they are caught
  when the workflow is linked rather than when it is read

It does NOT catch (intentional limit — keeps the validator local and the
store simple):

- `{ ref: step.X.Y }` field-level refs against runtime value shape
- cross-workflow refs (dispatch child results)

Use `forge workflow check` for the same shallow checks without a daemon.
Use external tooling (e.g. dispatch with sample inputs) for the deeper
checks.
