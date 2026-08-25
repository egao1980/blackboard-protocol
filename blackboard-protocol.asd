(defsystem "blackboard-protocol"
  :version "0.1.0"
  :description "AI-agnostic KSAR blackboard + COW workspaces for cl-stack"
  :author "egao1980"
  :license "MIT"
  :depends-on ("bordeaux-threads")
  :properties (:cl-repo (:ci (:with ("capability-protocol") :sources (("bordeaux-threads" :ql) ("rove" :ql)))))
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "conditions")
               (:file "blackboard")
               (:file "workspace")
               (:file "ks")
               (:file "scheduler"))
  :in-order-to ((test-op (test-op "blackboard-protocol/tests"))))

(defsystem "blackboard-protocol/tests"
  :depends-on ("blackboard-protocol" "capability-protocol" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "helpers")
               (:file "sections-test")
               (:file "watchers-test")
               (:file "workspace-test")
               (:file "scheduler-test")
               (:file "ks-test")
               (:file "coding-agent-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
