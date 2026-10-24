# Workflow Spec

A workflow is a Warp program. It is written in YAML in the notation of the
Warp YAML front end (`warp-frontend-yaml`, its README), which turns it into a
canonical document that the Warp runtime loads, builds and runs. The language
itself, its constructs, types and standard vocabulary, is the Warp
specification's. This page says what Forge adds: how a workflow file is laid
out, and the verbs a workflow writes, which Forge's library declares over the
native procedures the daemon lends a run.

## The file

A workflow file declares exactly one procedure, named after the file: the file
`echo.yaml` declares `procedures: { echo: … }`, and that name is the workflow's
identity in the catalog. The procedure is `access: public`, since a run starts
from it. Another workflow calls it by that name, so the name is not a short
name the library or std gives (`run`, `count`) or a key the notation spells
as an operator (`is`): a file taking one is refused at its own file, and the
other files are read without it.

The catalog reads every file leaning on the library and on the other files,
so a workflow names a verb, or another workflow, by its short name and hands
its arguments by name. At each reload every file is built against the
library, the natives under it, the standard vocabulary and the files that
build; a file that does not load or does not build is listed with its refusal
and left out of every run. A run is built from the dispatched workflow and
every file that built. A workflow calls another one in the same run with
`call`, by its name, and starts another run with `dispatch`.

An inline spec, handed to `workflow.dispatch` or `schedule.create` in place
of a name, is one procedure written as an object in the same notation, with
no name. It is read the way a file is, leaning on the library and on the
catalog's files, and runs under the name `<inline>`.

- **Inputs** are the procedure's parameters. A caller hands them by name. An
  input of an optional type (`String?`) may be left out, and the daemon hands
  it null; any other input must be handed.
- **The result** is what the procedure returns. The fields of a struct or the
  entries of a map are the run's outputs, any other value is the one output
  `result`, and null is none.
- **Failures** the body lets out are declared under `failing`, as the language
  asks of any procedure.

An input with a value it takes when left out writes it under `default:`, as
the front end reads it: the input reads `String?` to a caller, so the daemon
hands it null when left out, and the body starts by settling the default.

```yaml
parameters: [ who: { type: String, default: world } ]
```

A workflow's `description:` and each input's `hint:` are prose the front end
hands back beside the document: `workflow list` prints the description, and
`workflow describe` prints it and each input's hint.

```yaml
procedures:
  greet:
    description: Says hello.
    access: public
    parameters: [ who: { type: String, hint: whom to greet } ]
    returns: String
    result: { format: "hello, ${who}", with: { who: { ref: who } } }
```

## The `Forge` library

The verbs are the procedures of Forge's library, a document in the front
end's notation (`lib/Forge.yaml`) that the binary carries and every workflow
leans on. A verb is written by its short name, and its arguments by name, in
any order; an optional one left out is null, and one with a default takes
it:

```yaml
- let: listed
  value: { call: { procedure: shell, arguments: { command: [ls, -la], timeout: 30 } } }
- let: reply
  value: { agent: hello }
```

A verb with one argument may be written as a mapping of its name to the
argument, as `agent` is above. A closure handed to a verb takes from the verb
what its signature leaves out, so `invoke`'s body writes only what it returns
and its statements. Every verb may run beside another in a fan-out.

Under each verb is the native procedure the daemon implements,
`Forge.Native.<verb>`, which takes every argument by position, defaults
settled. A workflow writes the library's verbs.

A step is a call of a verb that acts outside the program, from its native's start to its return or throw.

### `Forge.shell`

`shell(command: Array<String>, cwd: String?, env: Dictionary<String, String>, stdin: String?, timeout: Double?) -> String`,
failing `nonzero_exit`, `timeout`. `env` defaults to an empty map.

Runs `command[0]` with the rest as its arguments, holding one of the daemon's
step slots for the whole run, and returns its standard output. `cwd` left out
is the daemon's own, and `env` is set over the daemon's environment. A nonzero
exit fails with `nonzero_exit`, whose details are `exit_code`, `stderr` and
`stdout`. A command still running after `timeout` seconds fails with
`timeout`, whose details are `seconds`.

### `Forge.extract`

`extract(text: String, outputs: Dictionary<String, Any>) -> Dictionary<String, Any>`, const,
failing `extract_refused`.

Reads the values `outputs` names out of `text` (see *Output extractors*) and
returns them by name, with the whole text under `_raw`. It reaches nothing
outside the run. A text that does not hold what `outputs` asks (a path that
is not there and has no `default`, a regex that does not match, a value that
does not coerce to its type) fails with `extract_refused`, which a rescue may
take. What `outputs` itself gets wrong (a map that is no extractor, the key
`_raw`, a path or a regex that does not parse) is the workflow's defect: it
is refused before the text is read, and no rescue takes it.

### `Forge.invoke`

`invoke(model: String?, allowed: Array<Any>?, env_extra: Dictionary<String, String>, cwd: String?, permission_mode: String?, share_session: Bool, timeout: Double?, body: () throws -> some Result) -> some Result`,
failing anything. `env_extra` defaults to an empty map and `share_session` to
`false`.

Opens an agent session with these settings and calls `body` inside it; what
the body returns is what `invoke` returns, so the body writes its `returns`.
`model` is `<provider>[:<model>]`. `allowed` is the list of tools to expose,
each a name or a map of `command` to a pattern; left out, the backend's own
setting stands, and `[]` exposes none. `cwd` and `permission_mode` left out are
unset; an empty string is refused. `share_session: true` reuses the session of
an enclosing `invoke` where there is one. A session still open after `timeout`
seconds fails with `timeout`.

```yaml
- let: answer
  value:
    call:
      procedure: invoke
      arguments:
        model: claude
        body: { closure: { returns: String, result: { agent: hello } } }
```

### `Forge.agent`

`agent(prompt: String) -> String`, failing `nonzero_exit`.

One prompt turn in the session the enclosing `invoke` opened, holding a step
slot. Outside a session it is refused. A piece of a fan-out speaks to no
session it did not open. A turn its backend refuses (a nonzero exit of the
agent's CLI, an HTTP error below 500) fails with `nonzero_exit`, whose details
are `exit_code`, `stderr` and `stdout`.

### `Forge.dispatch`

`dispatch(name: String, inputs: Dictionary<String, Any>, timeout: Double?) -> Dictionary<String, Any>`,
failing `child_run_failed`, `timeout`. `inputs` defaults to an empty map.

Runs the catalog workflow `name` as a run of its own, with its own policy
check, slot and ledger, and returns its outputs. A child that fails at its
work fails with `child_run_failed`, which a rescue may take. A child the
policy refuses, or one that faults or is cancelled, fails the parent past any
rescue.

### `Forge.resource`

`resource(content: String, inputs: Dictionary<String, Any>) -> String`.
`inputs` defaults to an empty map.

Reads the resource file `content`, relative to the resource directory, and
renders it as a template over `inputs`: `${name}` stands for the input of that
name and `$${` writes `${`. A null input is written `null`, as the language's
`format` writes it, and a name the inputs do not hold is refused. An input
that must not be null is declared without `?`.

### `Forge.locate`

`locate(path: String) -> String`.

The absolute path of the resource file `path`, which is not read.

### `Forge.run`

`run() -> Forge.Run`, where `Forge.Run` is `{ workflow_id: String, root_id: String }`.

This run's id, and the id of the run that started the chain.

### `Forge.origin`

`origin() -> Forge.Origin`, where `Forge.Origin` is `{ kind: String, id: String? }`.

What started this run, and the id of the schedule or caller where there is one.

## Concurrency

Pieces of work run at once through `Standard.Concurrent.allKeyed` (or `all`),
each piece an isolated closure. The front end completes a piece from its slot
and the piece writes what it returns:

```yaml
- let: both
  value:
    call:
      procedure: Standard.Concurrent.allKeyed
      arguments:
        - dictionary:
            - [left, { closure: { returns: Int, result: 1 } }]
            - [right, { closure: { returns: Int, result: 2 } }]
```

## Output extractors

`extract` reads a text, usually what `shell` returned; every other
verb speaks structured values already. The `outputs` argument is a map from a
name to an extractor. Shorthand (bare JSONPath):

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
| `type` | `string` (default) / `int` / `float` / `bool` / `json`, coerced to it |
| `default` | fallback value when missing. A declared `default` (even `null`) means a missing path does not fail the call; leaving `default` out makes the path mandatory, and a missing one fails the call with `extract_refused` |
| `hint` | human description |

## A complete workflow

A tour of the language a workflow is written in, with no verb that reaches
outside the run.

```yaml runnable
procedures:
  tour:
    access: public
    parameters: [ who: { type: String, default: world } ]
    returns: "Dictionary<String, Any>"
    failing: [aborted, concurrent_failed]
    body:
      - let: greeting
        value: { format: "hello, ${who}", with: { who: { ref: who } } }
      - var: branch
        type: String
        value: ""
      - value:
          cases:
            - when: { of: { ref: who }, is: world }
              then: [ { set: branch, value: took-a } ]
            - else: [ { set: branch, value: took-b } ]
      - var: rounds
        type: Int
        value: 0
      - value:
          loop:
            while: { of: { ref: rounds }, is_not: 2 }
            body:
              - set: rounds
                value: { of: { ref: rounds }, plus: 1 }
      - var: walk
        type: "Array<String>"
        value: []
      - let: walked
        value:
          each:
            of: [ one, two ]
            as: item
            index: at
            body:
              - set: walk
                value: { of: { ref: walk }, appending: { format: "${at}:${item}", with: { at: { ref: at }, item: { ref: item } } } }
      - let: parallel
        value:
          call:
            procedure: Standard.Concurrent.allKeyed
            arguments:
              - dictionary:
                  - [left, { closure: { returns: Int, result: 1 } }]
                  - [right, { closure: { returns: Int, result: 2 } }]
      - var: rescued
        type: String
        value: ""
      - let: caught
        value:
          attempt:
            body:
              - value: { abort: bail out }
            rescue:
              - set: rescued
                value: { format: "rescued: ${message}", with: { message: { ref: caught.message } } }
    result:
      dictionary:
        - [greeting, { ref: greeting }]
        - [branch, { ref: branch }]
        - [loop, { ref: rounds }]
        - [walk, { ref: walk }]
        - [parallel, { ref: parallel }]
        - [rescued, { ref: rescued }]
```
