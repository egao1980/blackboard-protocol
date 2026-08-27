(defpackage #:blackboard-protocol
  (:use #:cl)
  (:nicknames #:stack-blackboard)
  (:local-nicknames (#:bt2 #:bordeaux-threads))
  (:export
   ;; conditions
   #:blackboard-error
   #:blackboard-error-message
   #:workspace-error
   #:workspace-merge-conflict
   #:workspace-merge-conflict-key
   #:workspace-merge-conflict-parent-value
   #:workspace-merge-conflict-child-value
   #:scheduler-timeout
   #:unknown-ks
   #:unknown-ks-name
   #:require-ks
   #:call-with-blackboard-restarts
   #:with-blackboard-restarts
   #:invoke-retry
   #:invoke-use-value
   #:invoke-use-parent
   #:invoke-use-child
   #:invoke-skip
   #:auto-use-parent
   #:auto-use-child
   #:auto-retry
   #:with-auto-use-parent
   #:with-auto-use-child

   ;; blackboard
   #:blackboard
   #:make-blackboard
   #:blackboard-max-concurrency
   #:read-section
   #:write-section
   #:remove-section
   #:list-sections
   #:section-bound-p

   ;; watchers
   #:watcher
   #:watcher-id
   #:watcher-requires
   #:watcher-handler
   #:watcher-priority
   #:watcher-one-shot-p
   #:watch
   #:unwatch
   #:get-watcher
   #:list-watchers

   ;; KSAR
   #:ksar
   #:ksar-id
   #:ksar-watcher-id
   #:ksar-workspace
   #:ksar-blackboard
   #:ksar-handler
   #:ksar-triggered-key
   #:ksar-priority
   #:ksar-context
   #:ksar-status
   #:ksar-step
   #:enqueue-ksar
   #:requeue-ksar
   #:agenda-contents
   #:agenda-size

   ;; scheduler
   #:run-scheduler
   #:start-scheduler
   #:stop-scheduler
   #:wait-until-idle
   #:scheduler-running-p

   ;; workspaces
   #:workspace
   #:workspace-name
   #:workspace-parent
   #:workspace-blackboard
   #:workspace-status
   #:workspace-max-steps
   #:workspace-step-count
   #:fork-workspace
   #:merge-workspace
   #:discard-workspace
   #:cancel-workspace
   #:list-workspaces
   #:get-workspace
   #:find-root-bb

   ;; knowledge sources
   #:knowledge-source
   #:ks-name
   #:ks-version
   #:ks-priority
   #:ks-precondition
   #:ks-execute
   #:ks-postcondition
   #:register-ks
   #:unregister-ks
   #:get-ks
   #:list-ks))

(in-package #:blackboard-protocol)
