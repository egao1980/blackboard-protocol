(defpackage #:capability-protocol
  (:use #:cl)
  (:nicknames #:stack-capability)
  (:local-nicknames (#:bt2 #:org.shirakumo.bordeaux-threads))
  (:import-from #:blackboard-protocol
                #:blackboard
                #:blackboard-error
                #:blackboard-error-message)
  (:export
   #:capability-error
   #:unknown-capability
   #:unknown-capability-name
   #:unknown-operation
   #:unknown-operation-name
   #:unknown-operation-capability

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
   #:register-capability
   #:unregister-capability
   #:get-capability
   #:list-capabilities
   #:defcapability

   ;; abstract domains — GF names only; adapters implement
   #:compute-capability
   #:code-editing-capability
   #:version-control-capability
   #:web-search-capability
   #:communication-capability
   #:llm-generation-capability
   #:run-command
   #:read-file
   #:write-file
   #:git-status
   #:web-search
   #:send-message
   #:complete))

(in-package #:capability-protocol)
