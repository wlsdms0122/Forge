# Workflow Spec

A workflow is a Warp program. It is written in YAML in the notation of the
Warp YAML front end (`warp-frontend-yaml`, its README), which turns it into a
canonical document that the Warp runtime loads, builds and runs. The language
itself, its constructs, types and standard vocabulary, is the Warp
specification's. This page says what Forge adds: how a workflow file is laid
out, and the verbs the daemon lends a run as the `Forge` module.

## The file

A workflow file declares exactly one procedure, named after the file: the file
`echo.yaml` declares `procedures: { echo: … }`, and that name is the workflow's
identity in the catalog. The procedure is `access: public`, since a run starts
from it.

Every run is built from the dispatched workflow, every other workflow in the
catalog, the `Forge` module and the standard vocabulary. A workflow calls
another one in the same run with `call`, by its name, and starts another run
with `Forge.dispatch`.

- **Inputs** are the procedure's parameters. A caller hands them by name. An
  input of an optional type (`String?`) may be left out, and the daemon hands
  it null; any other input must be handed.
- **The result** is the struct or map the procedure returns. Its fields are the
  run's outputs.
- **Failures** the body lets out are declared under `failing`, as the language
  asks of any procedure.

A value an author wants when an input is left out is settled at the top of the
body:

```yaml
parameters: [ who: String? ]
failing: [cast_refused]
body:
  - var: name
    type: String
    value: world
  - value:
      conditional:
        when: { present: { ref: who } }
        then: [ { set: name, value: { as: { of: { ref: who }, type: String } } } ]
```

## The `Forge` module

The verbs are native procedures. They are called like any procedure, every
argument written in the order the procedure declares it, null where an
optional one says nothing. Each one may run beside another in a fan-out.

### `Forge.shell`

`Forge.shell(command: Array<String>, cwd: String?, env: Dictionary<String, String>?, stdin: String?, outputs: Dictionary<String, Any>?, timeout: Double?) -> Any`,
failing `nonzero_exit`, `timeout`.

Runs `command[0]` with the rest as its arguments, holding one of the daemon's
step slots for the whole run. It returns the standard output as a string, or,
where `outputs` is handed, the map its extractors read out of it (see *Shell
output extractors*). A nonzero exit fails with `nonzero_exit`, whose details
are `exit_code`, `stderr` and `stdout`. A command still running after
`timeout` seconds fails with `timeout`, whose details are `seconds`.

### `Forge.invoke`

`Forge.invoke<Result>(model: String?, allowed: Any, env_extra: Dictionary<String, String>?, cwd: String?, permission_mode: String?, share_session: Bool?, timeout: Double?, body: () throws -> Result) -> Result`,
failing anything.

Opens an agent session with these settings and calls `body` inside it; what
the body returns is what `invoke` returns. `model` is
`<provider>[:<model>]`. `allowed` is the list of tools to expose, or null for
the backend's own setting. `cwd` and `permission_mode` are null for unset; an
empty string is refused. `share_session: true` reuses the session of an
enclosing `invoke` where there is one. A session still open after `timeout`
seconds fails with `timeout`.

### `Forge.agent`

`Forge.agent(prompt: String) -> String`.

One prompt turn in the session the enclosing `Forge.invoke` opened, holding a
step slot. Outside a session it is refused. A piece of a fan-out speaks to no
session it did not open.

### `Forge.dispatch`

`Forge.dispatch(name: String, inputs: Dictionary<String, Any>?, timeout: Double?) -> Dictionary<String, Any>`,
failing `child_run_failed`, `timeout`.

Runs the catalog workflow `name` as a run of its own, with its own policy
check, slot and ledger, and returns its outputs. A child that fails at its
work fails with `child_run_failed`, which a rescue may take. A child the
policy refuses, or one that faults or is cancelled, fails the parent past any
rescue.

### `Forge.resource`

`Forge.resource(content: String, inputs: Dictionary<String, Any>?) -> String`.

Reads the resource file `content`, relative to the resource directory, and
renders it as a template over `inputs`: `${name}` stands for the input of that
name and `$${` writes `${`. A name the inputs do not hold, or hold as null, is
refused.

### `Forge.locate`

`Forge.locate(path: String) -> String`.

The absolute path of the resource file `path`, which is not read.

### `Forge.run`

`Forge.run() -> Forge.Run`, where `Forge.Run` is `{ workflow_id: String, root_id: String }`.

This run's id, and the id of the run that started the chain.

### `Forge.origin`

`Forge.origin() -> Forge.Origin`, where `Forge.Origin` is `{ kind: String, id: String? }`.

What started this run, and the id of the schedule or caller where there is one.

## Concurrency

Pieces of work run at once through `Standard.Concurrent.allKeyed` (or `all`),
each piece an isolated closure:

```yaml
- let: both
  value:
    call:
      procedure: Standard.Concurrent.allKeyed
      arguments:
        - dictionary:
            - [left, { closure: { isolated: true, returns: Int, result: 1 } }]
            - [right, { closure: { isolated: true, returns: Int, result: 2 } }]
```

## Shell output extractors

Only `Forge.shell` decomposes its stdout; every other verb speaks structured values
already. The `outputs` argument is a map from a name to an extractor. Shorthand (bare JSONPath):

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

## A complete workflow

A tour of the language a workflow is written in, with no verb that reaches
outside the run.

```yaml runnable
procedures:
  tour:
    access: public
    parameters: [ who: String? ]
    returns: "Dictionary<String, Any>"
    failing: [aborted, cast_refused, concurrent_failed]
    body:
      - var: name
        type: String
        value: world
      - value:
          conditional:
            when: { present: { ref: who } }
            then: [ { set: name, value: { as: { of: { ref: who }, type: String } } } ]
      - let: greeting
        value: { format: "hello, ${name}", with: { name: { ref: name } } }
      - var: branch
        type: String
        value: ""
      - value:
          cases:
            - when: { of: { ref: name }, is: world }
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
                  - [left, { closure: { isolated: true, returns: Int, result: 1 } }]
                  - [right, { closure: { isolated: true, returns: Int, result: 2 } }]
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
