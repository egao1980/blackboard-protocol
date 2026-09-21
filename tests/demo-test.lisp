(in-package #:capability-protocol/tests)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (load (asdf:system-relative-pathname "capability-protocol"
                                       "examples/decision-interceptor.lisp")))

(deftest decision-interceptor-demo-runs
  (let ((decision (capability-protocol/demo:run (make-broadcast-stream))))
    (ok (typep decision 'capability-protocol:policy-decision))
    (ok (eq :ask (capability-protocol:decision-kind decision)))))
