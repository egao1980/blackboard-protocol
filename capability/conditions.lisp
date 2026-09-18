(in-package #:capability-protocol)

(define-condition capability-error (blackboard-error)
  ())

(define-condition unknown-capability (capability-error)
  ((name :initarg :name :reader unknown-capability-name))
  (:report (lambda (c s)
             (format s "Unknown capability ~S~@[: ~A~]"
                     (unknown-capability-name c)
                     (blackboard-error-message c)))))

(define-condition unknown-catalogue (capability-error)
  ((name :initarg :name :reader unknown-catalogue-name))
  (:report (lambda (c s)
             (format s "Unknown catalogue ~S~@[: ~A~]"
                     (unknown-catalogue-name c)
                     (blackboard-error-message c)))))

(define-condition unknown-operation (capability-error)
  ((name :initarg :name :reader unknown-operation-name)
   (capability :initarg :capability :reader unknown-operation-capability))
  (:report (lambda (c s)
             (format s "Unknown operation ~S on capability ~S~@[: ~A~]"
                     (unknown-operation-name c)
                     (if (unknown-operation-capability c)
                         (capability-name (unknown-operation-capability c))
                         nil)
                     (blackboard-error-message c)))))

(define-condition policy-denied (capability-error)
  ((invocation :initarg :invocation :reader policy-denied-invocation :initform nil)
   (decision :initarg :decision :reader policy-denied-decision :initform nil)
   (reason :initarg :reason :reader policy-denied-reason :initform nil))
  (:report (lambda (c s)
             (let* ((inv (policy-denied-invocation c))
                    (cap (and inv (invocation-capability inv)))
                    (op (and inv (invocation-operation inv))))
               (format s "Capability policy denied ~S on ~S~@[: ~A~]"
                       op
                       (and cap (capability-name cap))
                       (or (policy-denied-reason c)
                           (blackboard-error-message c)))))))

(define-condition policy-ask (condition)
  ((invocation :initarg :invocation :reader policy-ask-invocation :initform nil)
   (decision :initarg :decision :reader policy-ask-decision :initform nil)
   (prompt :initarg :prompt :reader policy-ask-prompt :initform nil))
  (:report (lambda (c s)
             (let* ((inv (policy-ask-invocation c))
                    (op (and inv (invocation-operation inv))))
               (format s "Capability policy asks for approval of ~S~@[ (~A)~]"
                       op
                       (or (policy-ask-prompt c)
                           (let ((d (policy-ask-decision c)))
                             (and d (decision-reason d))))))))
  (:documentation
   "Non-error control condition (like MCP-INPUT-REQUIRED). Unhandled SIGNAL proceeds."))

(defun invoke-decline (&optional condition)
  (let ((r (find-restart 'decline condition)))
    (when r (invoke-restart r))))

(defun auto-skip (condition)
  (when (find-restart 'skip condition)
    (invoke-skip condition)))

(defmacro with-auto-skip (&body body)
  `(handler-bind ((unknown-capability #'auto-skip)
                  (unknown-operation #'auto-skip))
     ,@body))
