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

(defun invoke-use-value (value &optional condition)
  (let ((r (find-restart 'use-value condition)))
    (when r (invoke-restart r value))))

(defun invoke-skip (&optional condition)
  (let ((r (find-restart 'skip condition)))
    (when r (invoke-restart r))))

(defun auto-skip (condition)
  (if (find-restart 'skip condition)
      (invoke-skip condition)
      (error condition)))

(defmacro with-auto-skip (&body body)
  `(handler-bind ((unknown-capability #'auto-skip)
                  (unknown-operation #'auto-skip))
     ,@body))
