(in-package #:capability-protocol)

(defclass capability ()
  ((name :initarg :name :reader capability-name)
   (version :initarg :version :reader capability-version :initform "0.1.0")
   (description :initarg :description :reader capability-description :initform "")))

(defgeneric capability-operations (cap)
  (:method ((cap capability)) nil))

(defstruct capability-operation
  (name nil)
  (params nil)
  (returns nil)
  (doc "" :type string))

(defgeneric invoke-operation (cap op-name &rest args)
  (:documentation "Portable dynamic dispatch: look up OP-NAME as a GF and apply.
No SBCL eql-specializer / find-method."))

(defmethod invoke-operation ((cap capability) op-name &rest args)
  (let ((fn (and (symbolp op-name)
                 (fboundp op-name)
                 (fdefinition op-name))))
    (unless (typep fn 'generic-function)
      (error 'unknown-operation :capability cap :name op-name))
    (apply fn cap args)))

(defun %capability-table (bb)
  (blackboard-protocol::blackboard-capabilities
   (blackboard-protocol:find-root-bb bb)))

(defun %capability-lock (bb)
  (blackboard-protocol::blackboard-lock
   (blackboard-protocol:find-root-bb bb)))

(defgeneric register-capability (bb cap))
(defgeneric get-capability (bb name))
(defgeneric unregister-capability (bb name))
(defgeneric list-capabilities (bb))

(defmethod register-capability (bb (cap capability))
  (let ((lock (%capability-lock bb)))
    (bt2:with-lock-held (lock)
      (setf (gethash (capability-name cap) (%capability-table bb)) cap)))
  cap)

(defmethod get-capability (bb name)
  (let ((lock (%capability-lock bb)))
    (bt2:with-lock-held (lock)
      (gethash name (%capability-table bb)))))

(defmethod unregister-capability (bb name)
  (let ((lock (%capability-lock bb)))
    (bt2:with-lock-held (lock)
      (remhash name (%capability-table bb)))))

(defmethod list-capabilities (bb)
  (let ((lock (%capability-lock bb))
        (result nil))
    (bt2:with-lock-held (lock)
      (maphash (lambda (name cap)
                 (push (list :name name
                             :version (capability-version cap)
                             :operations (mapcar #'capability-operation-name
                                                 (capability-operations cap)))
                       result))
               (%capability-table bb)))
    result))
