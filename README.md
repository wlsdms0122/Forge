# Forge

Forge is a per-session daemon that runs **workflows written as pure data** —
shell work, LLM agent sessions, and cross-workflow dispatch, driven by a
small YAML-shaped language in which no string is ever secretly code.

It exists for one recurring situation: an operator (human or LLM runtime)
who needs long-running, repeatable, observable automations — "review this
diff adversarially", "consolidate memory nightly", "validate, retry, then
report" — and needs them to be *auditable artifacts*, not prompt spaghetti.
A workflow here is a file you can read, validate before running, diff in
review, and trust to mean exactly what it says.

- [Concepts](#concepts)
  - [Workflow](#workflow)
  - [Step](#step)
  - [Expression](#expression)
  - [Condition](#condition)
  - [Action — kernel and host](#action--kernel-and-host)
  - [Rescue](#rescue)
  - [Session](#session)
- [Philosophy](#philosophy)
  - [Everything is data](#everything-is-data)
  - [Judge at load, not mid-run](#judge-at-load-not-mid-run)
  - [Failures are loud and classified](#failures-are-loud-and-classified)
  - [Boundaries are signatures](#boundaries-are-signatures)
  - [The kernel owns structure; the host owns the world](#the-kernel-owns-structure-the-host-owns-the-world)
- [A complete example](#a-complete-example)
- [Using it](#using-it)
- [Documents](#documents)
- [Development](#development)

## Concepts

### Workflow

A workflow is one YAML file. Its identity is the filename; its body is a
signature (`inputs`), a program (`steps`), and a public surface (`outputs`):

```yaml
# review.yaml — identity comes from the basename, never the body
description: Review a diff and answer with a verdict.
parameters:
  target: string
  depth: { type: string, default: quick, oneOf: [quick, thorough] }
body:
  - id: diff
    shell: { command: [git, diff, { ref: target }] }
  - id: verdict
    agent: { format: "Review this diff (${d} pass):\n${body}",
             with: { d: { ref: depth }, body: { ref: diff } } }
result:
  verdict: { ref: verdict }
```

A directory of these files is a *catalog*. The daemon scans it, loads every
file through one decoder, and reports broken files individually — one bad
file blocks only its own name, never the catalog.

### Step

The execution unit. Every step has an `id` (its binding name), exactly one
action, and optionally a `when` gate and a `rescue` program:

```yaml
- id: search
  when: { present: { ref: query } }   # skipped → outputs null
  shell: { command: [rg, -n, { ref: query }] }
  rescue:                                     # runs only on recoverable failure
  - id: empty
    value: "no matches"
```

Steps run in order; each step's output binds under its id and is visible to
everything after it. Scopes nest and never leak: a `group`/`branch`/`loop`
body's bindings vanish when the body ends, and the block speaks with a
single value.

### Expression

Wherever a value is expected, an expression appears. There are exactly five
shapes, and a bare string is always literal text:

```yaml
value: hello                # scalar literal — strings are never re-parsed
value: { ref: diff }        # reference — read a binding, evaluated now
value: { value: { ref: x } }  # quotation — the payload is data, not evaluated
value: { format: "hi ${who}", with: { who: { ref: name } } }
value: { user: { ref: name }, tags: [a, b] }   # record / array
```

`format` is the only string interpolation, and it is *closed*: a
placeholder may name only a declared `with` binding — it cannot reach into
ambient scope, and an undeclared placeholder is a load error, not an empty
string.

### Condition

Predicates share the data discipline. A comparison is two keys — `of` (the
subject) and one operator — and both sides are expressions:

```yaml
when: { of: { ref: verdict.kind }, is: approve }
when: { of: { ref: count }, one_of: [1, 2, 3] }
when: { present: { ref: optional } }        # unary
when: { all: [ <Condition>, ... ] }                # and / or / not compose
```

The kernel owns equality and existence (`is`, `is_not`, `one_of`,
`present`); every other word (`contains`, `starts_with`, `regex`, …) lives
in a library that hosts extend. Vocabulary grows in the library — the
grammar never changes shape for a new word.

### Action — kernel and host

Each step carries exactly one action. **Kernel actions** are pure
structure — they perform no I/O:

| Action | Meaning |
|--------|---------|
| `value` | evaluate an expression |
| `group` | a nested scope with one output |
| `branch` | if / else-if / else |
| `loop` | while — with an optional `guard` iteration budget |
| `each` | for-each over an array the spec already holds |
| `parallel` | concurrent children, isolated scopes, one composite output |
| `use` | call another workflow in-process, against its signature |
| `abort` | throw, with a reason |

**Host actions** are everything that touches the world, registered on top
by the embedding host. The Forge daemon registers:

| Action | Meaning |
|--------|---------|
| `shell` | run an argv array (never a shell string) |
| `invoke` | open one LLM session; each `agent` step inside is one turn |
| `agent` | one turn in the ambient session |
| `dispatch` | ask the daemon for an isolated child run |
| `resource` | `content:` render a file as a closed template · `path:` locate it |
| `dynamic` | lower runtime-composed steps through the same decoder |

The kernel does not know these exist. A different host could register a
different set without touching the language.

### Rescue

`rescue` is a catch block that is a *program*, not a substitute value.
While it runs, the failure itself is readable as a value under the failed
step's id — every payload carries `type` and `message`, and each failure
adds its own vocabulary (a shell failure: `exit_code`, `stderr`, `stdout`):

```yaml
- id: checked
  shell: { command: [jq, -e, "."], stdin: { ref: draft } }
  rescue:
  - id: repair
    agent: { format: "invalid JSON — ${e}. fix it.",
             with: { e: { ref: checked.stderr } } }
```

The rescue's last step becomes the failed step's output, and the failure
binding disappears the moment the rescue answers — it never leaks.

### Session

Each named session (`--session dev`) is its own daemon: socket, config,
token, catalog, schedules. Agent conversations are sessions too: `invoke`
opens one LLM session and each `agent` step is one turn in it — so a
validate-and-retry loop *continues the same dialogue* instead of starting
over, and the model remembers what it already produced.

## Philosophy

### Everything is data

The classic failure mode of workflow engines is the string that becomes
code: a template rendered into a template, an output spliced into a
command, an interpolation that reaches further than anyone intended. Forge
removes the class instead of guarding instances — no value is ever
re-parsed into something live. A string is text. A reference is a `{ ref: }`
object. The two interpolation surfaces that do exist (`format` templates,
resource file bodies) are closed over declared bindings. Even
runtime-composed steps (`dynamic`) arrive as data and lower through the
same decoder and validator the load path uses.

The payoff is mechanical: `forge workflow check` can verify a whole catalog
— undeclared inputs, invisible step ids, unbound `format` placeholders —
with no daemon and no run, because the program's meaning is entirely in its
shape.

### Judge at load, not mid-run

Unknown keys, half-spelled forms, references to names that will never be
visible, an enum default that fails its own constraint, an invalid literal
regex — all of it fails when the file is read, before any run exists. There
are no legacy spellings and no fallback decoding: a spelling either is the
grammar or it is a load error. A workflow that loads is a workflow whose
structure is sound; what remains for runtime is the world, not the text.

### Failures are loud and classified

The kernel splits three things other engines blur:

- **Absence** — a name that was never bound. Conditions answer it by
  declared policy (`present: false`, `is: false`); reads fail loud.
- **Recoverable failure** — the world did not cooperate: nonzero exit,
  failed child run, exhausted loop budget, expired deadline, an author's
  own `abort`. Exactly this class is what `rescue` may absorb, and each
  failure crosses into the rescue as a readable value.
- **Author mistake** — shape misuse, a contract violation. Never absorbed:
  a rescue must not swallow a typo because it happened to sit near a
  timeout. Cancellation likewise always propagates.

### Boundaries are signatures

A workflow declares its inputs; callers are settled against that
declaration — undeclared names rejected, defaults applied, types
normalized — and only declared names exist inside. `outputs` is the mirror
image: the workflow's whole public surface. Calling in-process (`use`) is a
function call against the signature; asking the daemon for an isolated run
(`dispatch`) is `Process.run`, with its own run id, policy principal,
cycle/depth guards, and lifetime.

### The kernel owns structure; the host owns the world

The `Spec` target is the language: steps, scopes, expressions, conditions,
control flow. It performs no I/O and can be embedded by any host. The
`Forge` target is one such host — daemon, shell, agent sessions, resources,
policy, scheduling. The same split runs through the condition library
(kernel: equality and existence; host: vocabulary) and through failure
payloads (kernel: the binding mechanism; each error: its own fields). When
a capability is missing, the question is never "how do we extend the
grammar" — it is "which side owns this word".

## A complete example

Validate-and-retry with a bounded budget — the idiom that exercises most of
the language. The first check runs once outside the loop; the body rebinds
the same id, and the next round's `where` sees the rebound value:

```yaml
description: Produce Block Kit JSON that passes validation, or give up loudly.
parameters:
  request: string
body:
  - id: draft
    invoke:
      body:
      - id: draft
        agent: { format: "Compose Block Kit JSON for: ${r}",
                 with: { r: { ref: request } } }
      - id: checked
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
            agent: { format: "That failed validation — ${e}. Fix it.",
                     with: { e: { ref: checked } } }   # same session, same dialogue
          - id: checked
            shell: { command: [jq, -e, "."], stdin: { ref: fix } }
            rescue:
            - id: mark
              value: { format: "RETRY: ${why}", with: { why: { ref: checked.stderr } } }
          result: { ref: checked }
      result: { ref: checked }
result:
  blocks: { ref: draft }
```

Every piece is doing declared work: the session persists across retries,
the failure crosses into `rescue` as a value, the loop's budget is explicit
and its exhaustion is itself recoverable, and nothing in the file could
mean anything other than what it says.

## Using it

Forge ships as one binary; the CLI is the single surface — every consumer
invokes `forge` as a subprocess, and clients speak JSON-RPC to the daemon's
Unix socket underneath.

```sh
forge serve --session dev            # the daemon (one per session)
forge workflow list                  # catalog, with per-file load failures
forge workflow check <file>          # full validation, no daemon needed
forge workflow dispatch <name> --input key=value
forge status
```

The operational surface — sessions, config, tokens, schedules, services,
jobs, RPC methods — is documented in [API.md](document/API.md).

## Documents

| Document | Covers |
|----------|--------|
| [Spec.md](document/Spec.md) | the language: top level, inputs, steps, every action, conditions, expressions, scope and validation rules |
| [API.md](document/API.md) | the binary: CLI subcommands, configuration, sessions, and the JSON-RPC methods underneath |

The live source of truth is the Swift decoder; both documents track it.

## Development

```sh
swift build --package-path package
swift test  --package-path package          # unit + integration suites

swift build -c release --package-path package
test/run package/.build/release/ForgeCLI    # release e2e gate (~3s, 45 checks)
```

The e2e gate boots a real daemon against the in-repo session home
(`test/home`) with a stub agent, walks every user-facing feature shallowly,
and tears everything down. It is the last gate before a binary ships.

```
package/    Swift package
  Sources/Spec       the language kernel (no I/O)
  Sources/Forge      the host: daemon, shell, agent sessions, policy, config
  Sources/ForgeCLI   the `forge` command
document/   Spec.md (the language) · API.md (CLI/RPC)
test/       the release e2e gate — `test/run <binary>`
```
