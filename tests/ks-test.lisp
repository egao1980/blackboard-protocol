(in-package #:blackboard-protocol/tests)

(defclass echo-ks (knowledge-source)
  ())

(defmethod ks-precondition ((ks echo-ks) bb)
  (read-section bb :enabled :default nil))

(defmethod ks-execute ((ks echo-ks) bb)
  (write-section bb :out (read-section bb :in))
  :ok)

(defmethod ks-postcondition ((ks echo-ks) bb result)
  (write-section bb :result result)
  t)

(deftest ks-precondition-gates-handler
  (let ((bb (make-blackboard))
        (ks (make-instance 'echo-ks :name 'echo :priority 5)))
    (register-ks bb ks :requires '(:in))
    (write-section bb :in 42)
    (drain bb)
    (ok (eq :absent (read-section bb :out :default :absent))
        "precondition false → execute does not run")
    (write-section bb :enabled t)
    (write-section bb :in 43)
    (drain bb)
    (ok (eql 43 (read-section bb :out)))
    (ok (eq :ok (read-section bb :result)))))

(deftest ks-register-unwatch
  (let ((bb (make-blackboard))
        (ks (make-instance 'echo-ks :name 'echo)))
    (register-ks bb ks :requires '(:in))
    (ok (eq ks (get-ks bb 'echo)))
    (unregister-ks bb 'echo)
    (write-section bb :enabled t)
    (write-section bb :in 1)
    (drain bb)
    (ok (eq :absent (read-section bb :out :default :absent)))))

(deftest require-ks-use-value
  (let ((bb (make-blackboard))
        (ks (make-instance 'echo-ks :name 'echo)))
    (ok (null (get-ks bb 'echo)))
    (let ((got (handler-bind ((unknown-ks
                               (lambda (c)
                                 (use-value ks c))))
                 (require-ks bb 'echo))))
      (ok (eq ks got)))
    (ok (signals (require-ks bb 'echo) 'unknown-ks))))
