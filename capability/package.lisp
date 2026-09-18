(defpackage #:capability-protocol
  (:use #:cl)
  (:nicknames #:stack-capability)
  (:local-nicknames (#:bt2 #:bordeaux-threads))
  (:import-from #:blackboard-protocol
                #:blackboard
                #:blackboard-error
                #:blackboard-error-message
                #:invoke-use-value
                #:invoke-skip)
  (:export
   #:capability-error
   #:unknown-capability
   #:unknown-capability-name
   #:unknown-catalogue
   #:unknown-catalogue-name
   #:unknown-operation
   #:unknown-operation-name
   #:unknown-operation-capability
   #:invoke-use-value
   #:invoke-skip
   #:auto-skip
   #:with-auto-skip

   #:capability
   #:capability-name
   #:capability-version
   #:capability-description
   #:capability-operations
   #:capability-operation
   #:make-capability-operation
   #:capability-operation-name
   #:capability-operation-params
   #:capability-operation-returns
   #:capability-operation-doc
   #:invoke-operation
   #:operation-effect-class
   #:capability-operation-effect-class

   ;; policy interceptors (R1) — invoke-operation is the only public path
   #:interceptor
   #:interceptor-name
   #:interceptor-pre
   #:interceptor-post
   #:functional-interceptor
   #:make-interceptor
   #:operation-invocation
   #:invocation-capability
   #:invocation-operation
   #:invocation-args
   #:invocation-effect-class
   #:invocation-decisions
   #:invocation-retry-count
   #:policy-chain
   #:*policy-chain*
   #:make-policy-chain
   #:policy-chain-interceptors
   #:policy-chain-mode
   #:policy-chain-log
   #:add-interceptor
   #:with-policy-chain
   #:policy-decision
   #:make-decision
   #:decision-kind
   #:decision-reason
   #:decision-value
   #:decision-args
   #:decision-interceptor
   #:policy-denied
   #:policy-denied-invocation
   #:policy-denied-decision
   #:policy-denied-reason
   #:policy-ask
   #:policy-ask-invocation
   #:policy-ask-decision
   #:policy-ask-prompt
   #:invoke-decline

   #:register-capability
   #:unregister-capability
   #:get-capability
   #:require-capability
   #:list-capabilities
   #:capability-supported-p
   #:defcapability
   #:defcatalogue
   #:capability-catalogue
   #:make-capability-catalogue
   #:make-catalogue
   #:find-catalogue
   #:list-catalogues
   #:catalogue-name
   #:catalogue-description
   #:catalogue-defined-names
   #:catalogue-defines-p

   ;; abstract domains — GF names only; adapters implement
   #:compute-capability
   #:code-editing-capability
   #:version-control-capability
   #:web-search-capability
   #:communication-capability
   #:llm-generation-capability
   #:llm-tools-capability
   #:llm-vision-capability
   #:llm-audio-capability
   #:llm-video-capability
   #:llm-files-capability
   #:llm-speech-capability
   #:llm-transcription-capability
   #:llm-thinking-capability
   #:llm-structured-output-capability
   #:llm-responses-capability
   #:llm-embeddings-capability
   #:run-command
   #:read-file
   #:write-file
   #:git-status
   #:web-search
   #:send-message
   #:complete
   #:stream-complete
   #:upload-file
   #:synthesize
   #:transcribe
   #:embed))

(in-package #:capability-protocol)
