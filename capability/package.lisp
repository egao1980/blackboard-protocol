(defpackage #:capability-protocol
  (:use #:cl)
  (:nicknames #:stack-capability)
  (:local-nicknames (#:bt2 #:bordeaux-threads))
  (:import-from #:blackboard-protocol
                #:blackboard
                #:blackboard-error
                #:blackboard-error-message)
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
   #:register-capability
   #:unregister-capability
   #:get-capability
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
   #:transcribe))

(in-package #:capability-protocol)
