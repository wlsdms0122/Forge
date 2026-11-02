# Forge

Forge is a per-instance daemon that runs **workflows written as pure data**:
shell work, LLM agent sessions, and dispatch from one workflow to another,
driven by a small YAML-shaped language in which no string is ever secretly
code.

It exists for one recurring situation: an operator (human or LLM runtime)
who needs long-running, repeatable, observable automations ("review this
diff adversarially", "consolidate memory nightly", "validate, retry, then
report") and needs them to be *auditable artifacts*, not prompt spaghetti.
A workflow here is a file you can read, validate before running, diff in
review, and trust to mean exactly what it says.

- [Concepts](#concepts)
  - [Workflow](#workflow)
  - [Verbs](#verbs)
  - [Statements and expressions](#statements-and-expressions)
  - [Catch](#catch)
  - [Instance](#instance)
  - [Agent session](#agent-session)
- [Philosophy](#philosophy)
  - [Everything is data](#everything-is-data)
  - [Judge before the run](#judge-before-the-run)
  - [Failures are loud and classified](#failures-are-loud-and-classified)
  - [Boundaries are signatures](#boundaries-are-signatures)
  - [The language owns structure; Forge owns the world](#the-language-owns-structure-forge-owns-the-world)
- [A complete example](#a-complete-example)
- [Using it](#using-it)
- [Documents](#documents)
- [Development](#development)

## Concepts

### Workflow

A workflow is one YAML file, a Warp program written in the notation of the
Warp YAML front end. Its path is its identity: an absolute path as
written, or one relative to the working directory. A run starts from its
procedure `main`: its parameters are the workflow's inputs, what it returns
is its result, and `failing` says what it may fail with.

```yaml
# bot/review.yaml
procedures:
  main:
    description: Review a diff and answer with a verdict.
    access: public
    parameters:
      - target: { type: String, hint: the revision to diff against }
      - depth: { type: String, default: quick, hint: "quick or thorough" }
    returns: "Dictionary<String, Any>"
    failing: anything
    body:
      - let: diff
        value: { call: { procedure: shell, arguments: { command: [git, diff, { ref: target }] } } }
      - let: verdict
        value:
          call:
            procedure: invoke
            arguments:
              body:
                closure:
                  returns: String
                  result: { agent: { format: "Review this diff (${d} pass):\n${body}", with: { d: { ref: depth }, body: { ref: diff } } } }
    result: { dictionary: [ [verdict, { ref: verdict }] ] }
```

Each file is a program of its own. The daemon keeps no list of them: when a
run, a `dispatch` or a schedule names a path, it reads that one file
leaning on Forge's library alone and builds it, and builds it again only
where the file changed. A file that does not load, has no public `main` or
does not build is refused to whoever named it, and no other file is
touched.

### Verbs

The verbs a workflow reaches the world with (`shell`, `invoke`, `agent`,
`dispatch`, `resource`, `locate`, `extract`, `run`, `origin`) are the
procedures of Forge's library, a document written in the same notation that
the daemon carries and every workflow leans on. A verb is written by its
short name and its arguments by name; one left out takes the library's
default or null. Under each verb is a native procedure the daemon
implements, `Forge.Native.<verb>`, which takes its arguments by position.
[Spec.md](document/Spec.md) lists them.

### Statements and expressions

Everything else is the language's: `let` and `var`, `set`, conditionals,
`cases`, loops, `each`, fan-out through `Standard.Concurrent.allKeyed`,
calls to the file's own procedures, and expressions (`{ ref: x }`, operator
mappings such as `{ of: x, plus: 1 }`, `format` templates, dictionary
literals). A bare
string is always literal text, and `format` is closed over the bindings it
declares under `with`. The front end's README documents the notation.

### Catch

`try` runs a body and, when it fails with a declared failure, a
`catch`. Inside the catch the failure is readable under the try's
name: `type`, `message` and `details`, which each failure fills with its
own fields (a shell failure: `exit_code`, `stderr`, `stdout`).

```yaml
- let: checked
  value:
    try:
      body:
        - value: { call: { procedure: shell, arguments: { command: [jq, -e, .], stdin: { ref: draft } } } }
      catch:
        - set: draft
          value: { agent: { format: "invalid JSON: ${e}. Fix it.", with: { e: { ref: 'checked.details["stderr"]' } } } }
```

### Instance

Each named instance (`--instance dev`) is its own daemon with its own home,
`<XDG_CONFIG_HOME | ~/.config>/forge/<instance>`: the socket, `config.toml`,
policy, logs, and the state that outlives a restart (jobs, schedules,
service records). Workflows and the files they read live in the instance's
working directory, `<home>/document` unless the config names another.

### Agent session

`invoke` opens one LLM session around a body, and each `agent` call in it is
one turn, so a validate-and-retry loop *continues the same dialogue* instead
of starting over, and the model remembers what it already produced.

## Philosophy

### Everything is data

The classic failure mode of workflow engines is the string that becomes
code: a template rendered into a template, an output spliced into a
command, an interpolation that reaches further than anyone intended. Forge
removes the class instead of guarding instances: no value is ever re-parsed
into something live. A string is text. A reference is a `{ ref: }` object.
The two interpolation surfaces that do exist (`format` templates and
resource file bodies) are closed over the bindings they are handed.

The payoff is mechanical: `forge workflow check` reads workflow files the
way the daemon does, with no daemon and no run, because the program's
meaning is entirely in its text.

### Judge before the run

Unknown keys, a name nothing declares, a call that does not fit its
procedure's signature, a type that does not hold, a failure the
declaration does not admit: the front end, the load or the build refuses
each when the file is read, before its run starts. There are no legacy
spellings and no fallback reading. A workflow that runs is one that built;
what remains for runtime is the world, not the text.

### Failures are loud and classified

Three things stay apart:

- **Absence**: null is a value, an Optional input is declared `T?`, and an
  input that must not be absent is declared `T`, so the build refuses
  handing it null.
- **Recoverable failure**: the world did not cooperate. A nonzero exit, a
  failed child run, an expired deadline, a text that does not hold what an
  extraction asks, an author's own `abort`. Each is declared under
  `failing`, and exactly this class is what a `catch` may take.
- **Fault**: what no declaration admits, a policy denial, cancellation, an
  extractor that does not parse.
  Never taken by a catch, so a catch cannot swallow a defect that happened
  to sit near a timeout.

### Boundaries are signatures

A workflow's parameters are its inputs. A caller hands them by name, an
Optional one may be left out and is handed null, and a default is the
declaration's, settled first in the body. What the procedure returns is its
whole public surface. Another workflow is started with `dispatch`, which
asks the daemon for an isolated run, with its own run id, policy principal
and lifetime.

### The language owns structure; Forge owns the world

Warp is the language: statements, scopes, expressions, types, failures and
control flow, with no I/O. Forge is a host of it: it lends a run the native
verbs that touch the world (processes, agent sessions, resources, child
runs) and writes its grammar over them as a library in the language's own
notation, where the verbs' names, parameter names, defaults and closure
types are decided. When a capability is missing, the question is never how
to extend the grammar; it is which side owns the word.

## A complete example

Validate-and-retry with a bounded budget, the idiom that exercises most of
the language. The session persists across rounds, so each fix continues
the same dialogue:

```yaml
procedures:
  main:
    description: Produce Block Kit JSON that passes validation, or give up loudly.
    access: public
    parameters: [ request: { type: String, hint: what the message says } ]
    returns: String
    failing: anything
    body:
      - let: blocks
        value:
          call:
            procedure: invoke
            arguments:
              model: claude
              body:
                closure:
                  returns: String
                  body:
                    - var: draft
                      type: String
                      value: { agent: { format: "Compose Block Kit JSON for: ${r}", with: { r: { ref: request } } } }
                    - var: valid
                      type: Bool
                      value: false
                    - var: rounds
                      type: Int
                      value: 0
                    - value:
                        loop:
                          while: { not: { ref: valid } }
                          body:
                            - set: rounds
                              value: { of: { ref: rounds }, plus: 1 }
                            - let: checked
                              value:
                                try:
                                  body:
                                    - value: { call: { procedure: shell, arguments: { command: [jq, -e, .], stdin: { ref: draft } } } }
                                    - set: valid
                                      value: true
                                  catch:
                                    - value:
                                        conditional:
                                          when: { of: { ref: rounds }, is: 3 }
                                          then: [ { value: { abort: no valid Block Kit after three rounds } } ]
                                    - set: draft
                                      value: { agent: { format: "That failed validation: ${e}. Fix it.", with: { e: { ref: 'checked.details["stderr"]' } } } }
                  result: { ref: draft }
    result: { ref: blocks }
```

Every piece is doing declared work: the session persists across retries,
the failure crosses into `catch` as a value, the budget is explicit, its
exhaustion is an `abort` the declaration admits, and nothing in the file
could mean anything other than what it says.

## Using it

Forge ships as one binary, `forge`, built by `open-package build` to
`.build/forge` (see [Development](#development)); put it on `PATH`. The CLI
is the single surface: every consumer invokes `forge` as a subprocess, and
clients speak JSON-RPC to the daemon's Unix socket underneath.

```sh
forge serve --instance dev           # the daemon (one per instance)
forge workflow describe <path>       # a workflow's description and inputs
forge workflow check <file>...       # read as the daemon reads, no daemon needed
forge workflow dispatch <path> --inputs '{"key": "value"}'
forge status
```

The operational surface (instances, config, tokens, schedules, services,
jobs, RPC methods) is documented in [API.md](document/API.md).

## Documents

| Document | Covers |
|----------|--------|
| [Spec.md](document/Spec.md) | what Forge adds over the Warp language and its YAML front end: the workflow file, its inputs and result, and the verbs of the `Forge` library |
| [API.md](document/API.md) | the binary: CLI subcommands, configuration, instances, and the JSON-RPC methods underneath |

`DocumentTests` holds Spec.md to the `Forge` library and runs its tour.

## Development

The repository is an [open-package](https://github.com/wlsdms0122/open-package):
`manifest.toml` names what it can run, and `open-package` with no command
lists it.

```sh
open-package build           # the release binary, at .build/forge
open-package test            # unit and integration suites
open-package e2e             # build, then the release e2e gate on .build/forge
open-package embed-library   # after editing lib/Forge.yaml
```

The e2e gate (`test/run <binary>`) boots a real daemon against the in-repo
instance home (`test/home`) with a stub agent, walks every user-facing
feature shallowly, and tears everything down. It is the last gate before a
binary ships.

The version is `[package] version` in `manifest.toml`. The `PackageVersion`
build plugin writes it into the binary at every build, so `forge --version`,
`forge status` and `runtime.json` report the manifest's number.

The library is edited in `lib/Forge.yaml`. The binary carries a copy of it,
`Library.swift`, which `tool/embed-library.sh` writes; run it after an edit.
`ForgeVocabularyTests` holds the copy to the file, so an edit that was not
embedded is a red test.

```
manifest.toml   the open-package manifest: version, requirements, commands
package/        Swift package
  Sources/Forge              the host: daemon, shell, agent sessions, policy,
                             config, and the embedded copy of the library
  Sources/ForgeCLI           the `forge` command
  Sources/PackageVersionTool reads the manifest's version for the plugin
  Plugins/PackageVersion     the build plugin that hands Forge its version
lib/            Forge.yaml, the library the verbs are written in
tool/           build.sh (the binary) and embed-library.sh (the library copy)
document/       Spec.md (workflows and verbs) and API.md (CLI and RPC)
test/           the release e2e gate, `test/run <binary>`
```
