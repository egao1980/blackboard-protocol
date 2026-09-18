(defsystem "capability-protocol"
  :version "0.2.2"
  :description "CLOS capability protocol: defcapability / defcatalogue + policy interceptors"
  :author "egao1980"
  :license "MIT"
  :depends-on ("blackboard-protocol")
  :serial t
  :pathname "capability"
  :components ((:file "package")
               (:file "conditions")
               (:file "protocol")
               (:file "policy")
               (:file "macros")
               (:file "domains"))
  :in-order-to ((test-op (test-op "capability-protocol/tests"))))

(defsystem "capability-protocol/tests"
  :depends-on ("capability-protocol" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "capability-package")
               (:file "capability-test")
               (:file "policy-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
