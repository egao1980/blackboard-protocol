(in-package #:blackboard-protocol)

;;; Conditions + restarts (pathlib shape).

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

;;; --- restart helpers -------------------------------------------------------

(defun call-with-blackboard-restarts (thunk)
  "Establish RETRY / USE-VALUE around THUNK."
  (tagbody
   :retry
     (return-from call-with-blackboard-restarts
       (restart-case (funcall thunk)
         (retry ()
           :report "Retry the blackboard operation"
           (go :retry))
         (use-value (value)
           :report "Use a supplied value instead"
           :interactive (lambda ()
                          (format *query-io* "Value to use: ")
                          (force-output *query-io*)
                          (list (read *query-io*)))
           value)))))

(defmacro with-blackboard-restarts (&body body)
  `(call-with-blackboard-restarts (lambda () ,@body)))

(defun %invoke-retry ()
  (let ((r (find-restart 'retry)))
    (if r
        (invoke-restart r)
        (error "RETRY restart not active; wrap the call in WITH-BLACKBOARD-RESTARTS"))))

(defun invoke-retry (&optional condition)
  (let ((r (find-restart 'retry condition)))
    (when r (invoke-restart r))))

(defun invoke-use-value (value &optional condition)
  (let ((r (find-restart 'use-value condition)))
    (when r (invoke-restart r value))))

(defun invoke-use-parent (&optional condition)
  (let ((r (find-restart 'use-parent condition)))
    (when r (invoke-restart r))))

(defun invoke-use-child (&optional condition)
  (let ((r (find-restart 'use-child condition)))
    (when r (invoke-restart r))))

(defun invoke-skip (&optional condition)
  (let ((r (find-restart 'skip condition)))
    (when r (invoke-restart r))))

(defun auto-use-parent (condition)
  (if (find-restart 'use-parent condition)
      (invoke-use-parent condition)
      (error condition)))

(defun auto-use-child (condition)
  (if (find-restart 'use-child condition)
      (invoke-use-child condition)
      (error condition)))

(defun auto-retry (condition)
  (if (find-restart 'retry condition)
      (invoke-retry condition)
      (error condition)))

(defmacro with-auto-use-parent (&body body)
  `(handler-bind ((workspace-merge-conflict #'auto-use-parent))
     ,@body))

(defmacro with-auto-use-child (&body body)
  `(handler-bind ((workspace-merge-conflict #'auto-use-child))
     ,@body))
