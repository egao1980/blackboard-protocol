(defsystem "capability-protocol"
  :version "0.1.0"
  :description "CLOS capability protocol (defcapability + registry) on blackboard-protocol"
  :author "egao1980"
  :license "MIT"
  :depends-on ("blackboard-protocol")
  :serial t
  :pathname "capability"
  :components ((:file "package")
               (:file "conditions")
               (:file "protocol")
               (:file "macros")
               (:file "domains"))
  :in-order-to ((test-op (test-op "capability-protocol/tests"))))

(defsystem "capability-protocol/tests"
  :depends-on ("capability-protocol" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "helpers")
               (:file "capability-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
