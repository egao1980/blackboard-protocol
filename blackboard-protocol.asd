(defsystem "blackboard-protocol"
  :version "0.2.0"
  :description "AI-agnostic KSAR blackboard + COW workspaces for cl-stack"
  :author "egao1980"
  :license "MIT"
  :depends-on ("bordeaux-threads")
  :properties (:cl-repo
               (:provides ("blackboard-protocol" "capability-protocol")
                :ci (:with ("capability-protocol"
                            "blackboard-protocol/journal"))))
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "conditions")
               (:file "blackboard")
               (:file "workspace")
               (:file "ks")
               (:file "scheduler"))
  :in-order-to ((test-op (test-op "blackboard-protocol/tests"))))

(defsystem "blackboard-protocol/journal"
  :version "0.2.0"
  :description "task-protocol journal persistence for blackboard-protocol"
  :author "egao1980"
  :license "MIT"
  :depends-on ("blackboard-protocol" "task-protocol")
  :serial t
  :pathname "src/journal"
  :components ((:file "package")
               (:file "protocol"))
  :in-order-to ((test-op (test-op "blackboard-protocol/tests"))))

(defsystem "blackboard-protocol/tests"
  :depends-on ("blackboard-protocol" "capability-protocol"
               "blackboard-protocol/journal" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "helpers")
               (:file "sections-test")
               (:file "watchers-test")
               (:file "workspace-test")
               (:file "scheduler-test")
               (:file "ks-test")
               (:file "capability-package")
               (:file "capability-test")
               (:file "coding-agent-test")
               (:file "journal-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
