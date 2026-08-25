(in-package #:blackboard-protocol)

(define-condition blackboard-error (error)
  ((message :initarg :message :reader blackboard-error-message :initform nil))
  (:report (lambda (c s)
             (format s "Blackboard error~@[: ~A~]" (blackboard-error-message c)))))

(define-condition workspace-error (blackboard-error)
  ())

(define-condition workspace-merge-conflict (workspace-error)
  ((key :initarg :key :reader workspace-merge-conflict-key)
   (parent-value :initarg :parent-value :reader workspace-merge-conflict-parent-value)
   (child-value :initarg :child-value :reader workspace-merge-conflict-child-value))
  (:report (lambda (c s)
             (format s "Workspace merge conflict on ~S (parent ~S vs child ~S)~@[: ~A~]"
                     (workspace-merge-conflict-key c)
                     (workspace-merge-conflict-parent-value c)
                     (workspace-merge-conflict-child-value c)
                     (blackboard-error-message c)))))

(define-condition scheduler-timeout (blackboard-error)
  ()
  (:report (lambda (c s)
             (format s "Scheduler timed out waiting for idle~@[: ~A~]"
                     (blackboard-error-message c)))))

(define-condition unknown-ks (blackboard-error)
  ((name :initarg :name :reader unknown-ks-name))
  (:report (lambda (c s)
             (format s "Unknown knowledge source ~S~@[: ~A~]"
                     (unknown-ks-name c)
                     (blackboard-error-message c)))))
