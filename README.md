# blackboard-protocol

AI-agnostic **KSAR blackboard** + **CLOS capabilities** for [cl-stack](https://github.com/egao1980/cl-stack).

Extract of Demiurge **core** (sections, watchers, priority agenda, COW workspaces, `requeue-ksar`). **Zero** `mcp-protocol` / `a2a-protocol` / `ag-ui-protocol` / `llm-protocol` deps. Wire adapters live elsewhere.

| System | Role |
|--------|------|
| `blackboard-protocol` (`stack-blackboard`) | Sections, watchers, KSAR loop, COW workspaces |
| `capability-protocol` (`stack-capability`) | `defcapability` + registry on the board |

Briefs: [`blackboard.md`](https://github.com/egao1980/cl-stack/blob/main/docs/capabilities/blackboard.md) · [`capability.md`](https://github.com/egao1980/cl-stack/blob/main/docs/capabilities/capability.md) ([#192](https://github.com/egao1980/cl-stack/issues/192)–[#194](https://github.com/egao1980/cl-stack/issues/194)).

```lisp
(asdf:load-system "blackboard-protocol")
(asdf:load-system "capability-protocol")

(let ((bb (stack-blackboard:make-blackboard :max-concurrency 2)))
  (stack-blackboard:watch bb :id 'echo :requires '(:ping)
                          :handler (lambda (board ksar)
                                     (declare (ignore ksar))
                                     (stack-blackboard:write-section
                                      board :pong
                                      (stack-blackboard:read-section board :ping))))
  (stack-blackboard:write-section bb :ping 1)
  (stack-blackboard:run-scheduler bb :until-empty t)
  (stack-blackboard:read-section bb :pong))
```

Control path: `write-section` → watchers → KSAR → priority agenda → bounded workers. Continue a workspace with `requeue-ksar` (no trigger-key flicker). Serial-per-workspace; `max-concurrency` caps parallel *workspaces*.

## License

MIT — see [LICENSE](LICENSE).
