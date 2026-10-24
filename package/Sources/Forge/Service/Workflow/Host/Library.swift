//
//  Library.swift
//  Forge
//
//  Written by tool/embed-library.sh. Edit lib/Forge.yaml and run it again.
//

import Foundation

// The text of `lib/Forge.yaml`, as it stands in the repository.
enum Library {
    static let text = """
        # Forge's grammar: the verbs a workflow writes, each over the native verb
        # the daemon lends a run, with its parameters named, its defaults and the
        # closure type its body takes.
        name: Forge
        
        procedures:
          shell:
            description: Runs a command, holding one of the daemon's step slots while it runs, and returns what it wrote to standard output.
            access: public
            isolated: true
            parameters:
              - command: { type: Array<String>, hint: "the executable and its arguments" }
              - cwd: { type: String?, hint: "the directory it runs in, the daemon's own where left out" }
              - env: { type: "Dictionary<String, String>", default: { dictionary: [] }, hint: "variables set over the daemon's environment" }
              - stdin: { type: String?, hint: "what the command reads on its standard input" }
              - timeout: { type: Double?, hint: "seconds before the command fails with timeout" }
            returns: String
            failing: [nonzero_exit, timeout]
            result:
              call:
                procedure: Forge.Native.shell
                arguments: [ { ref: command }, { ref: cwd }, { ref: env }, { ref: stdin }, { ref: timeout } ]
        
          extract:
            description: Reads the values outputs names out of a text, usually what shell returned, and returns them by name with the whole text under _raw.
            access: public
            const: true
            isolated: true
            parameters:
              - text: String
              - outputs: { type: "Dictionary<String, Any>", hint: "a name and its extractor each: a JSONPath, or a mapping of path, regex or line with type and default" }
            returns: "Dictionary<String, Any>"
            failing: [extract_refused]
            result:
              call:
                procedure: Forge.Native.extract
                arguments: [ { ref: text }, { ref: outputs } ]
        
          invoke:
            description: Opens an agent session with these settings and calls body inside it. What body returns is what invoke returns.
            access: public
            isolated: true
            parameters:
              - model: { type: String?, hint: "<provider>[:<model>], the backend's own where left out" }
              - allowed: { type: "Array<Any>?", hint: "the tools the session may use, each a name or a mapping of command to a pattern; the backend's own setting where left out, and no tool for []" }
              - env_extra: { type: "Dictionary<String, String>", default: { dictionary: [] }, hint: "variables set over the agent's environment" }
              - cwd: { type: String?, hint: "the directory the session works in, the backend's own where left out" }
              - permission_mode: { type: String?, hint: "bypass, safe or restrict, the backend's own where left out" }
              - share_session: { type: Bool, default: false, hint: "reuse the session of an enclosing invoke where there is one" }
              - timeout: { type: Double?, hint: "seconds before the session fails with timeout" }
              - body: { type: "() throws -> some Result", hint: "the turns the session runs" }
            returns: some Result
            failing: anything
            result:
              call:
                procedure: Forge.Native.invoke
                arguments: [ { ref: model }, { ref: allowed }, { ref: env_extra }, { ref: cwd }, { ref: permission_mode }, { ref: share_session }, { ref: timeout }, { ref: body } ]
        
          agent:
            description: One prompt turn in the session the enclosing invoke opened, holding a step slot, and the reply.
            access: public
            isolated: true
            parameters: [ prompt: String ]
            returns: String
            failing: [nonzero_exit]
            result:
              call:
                procedure: Forge.Native.agent
                arguments: [ { ref: prompt } ]
        
          dispatch:
            description: Runs a catalog workflow as a run of its own, with its own policy check, slot and ledger, and returns its outputs.
            access: public
            isolated: true
            parameters:
              - name: { type: String, hint: "the catalog workflow to run" }
              - inputs: { type: "Dictionary<String, Any>", default: { dictionary: [] }, hint: "its inputs by name" }
              - timeout: { type: Double?, hint: "seconds before the child fails with timeout" }
            returns: "Dictionary<String, Any>"
            failing: [child_run_failed, timeout]
            result:
              call:
                procedure: Forge.Native.dispatch
                arguments: [ { ref: name }, { ref: inputs }, { ref: timeout } ]
        
          resource:
            description: Reads a resource file and renders it as a template over inputs.
            access: public
            isolated: true
            parameters:
              - content: { type: String, hint: "the file, relative to the resource directory" }
              - inputs: { type: "Dictionary<String, Any>", default: { dictionary: [] }, hint: "what ${name} in the file stands for" }
            returns: String
            result:
              call:
                procedure: Forge.Native.resource
                arguments: [ { ref: content }, { ref: inputs } ]
        
          locate:
            description: The absolute path of a resource file, which is not read.
            access: public
            isolated: true
            parameters:
              - path: { type: String, hint: "the file, relative to the resource directory" }
            returns: String
            result:
              call:
                procedure: Forge.Native.locate
                arguments: [ { ref: path } ]
        
          run:
            description: This run's id, and the id of the run that started the chain.
            access: public
            isolated: true
            returns: Forge.Run
            result: { call: { procedure: Forge.Native.run, arguments: [] } }
        
          origin:
            description: What started this run, and the id of the schedule or caller where there is one.
            access: public
            isolated: true
            returns: Forge.Origin
            result: { call: { procedure: Forge.Native.origin, arguments: [] } }
        """
}
