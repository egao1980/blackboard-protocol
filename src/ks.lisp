(in-package #:blackboard-protocol)

(defclass knowledge-source ()
  ((name :initarg :name :reader ks-name)
   (version :initarg :version :reader ks-version :initform "0.1.0")
   (priority :initarg :priority :accessor ks-priority :initform 0)))

(defgeneric ks-precondition (ks blackboard)
  (:method ((ks knowledge-source) bb)
    (declare (ignore bb))
    t))

(defgeneric ks-execute (ks blackboard))

(defgeneric ks-postcondition (ks blackboard result)
  (:method ((ks knowledge-source) bb result)
    (declare (ignore bb result))
    t))

(defun register-ks (bb ks &key requires one-shot)
  (let ((root (find-root-bb bb)))
    (bt2:with-lock-held ((blackboard-lock root))
      (setf (gethash (ks-name ks) (blackboard-ks-registry root)) ks)))
  (watch bb :id (ks-name ks)
         :requires requires
         :priority (ks-priority ks)
         :one-shot one-shot
         :handler (lambda (board ksar)
                    (declare (ignore ksar))
                    (when (ks-precondition ks board)
                      (ks-postcondition ks board (ks-execute ks board)))))
  ks)

(defun unregister-ks (bb name)
  (unwatch bb name)
  (let ((root (find-root-bb bb)))
    (bt2:with-lock-held ((blackboard-lock root))
      (remhash name (blackboard-ks-registry root))))
  name)

(defun get-ks (bb name)
  (let ((root (find-root-bb bb)))
    (bt2:with-lock-held ((blackboard-lock root))
      (gethash name (blackboard-ks-registry root)))))

(defun require-ks (bb name)
  "GET-KS or UNKNOWN-KS with USE-VALUE / SKIP."
  (or (get-ks bb name)
      (restart-case
          (error 'unknown-ks :name name)
        (use-value (ks)
          :report "Use a supplied knowledge source"
          ks)
        (skip ()
          :report "Treat the missing KS as NIL"
          nil))))

(defun list-ks (bb)
  (let ((root (find-root-bb bb)))
    (bt2:with-lock-held ((blackboard-lock root))
      (loop for ks being the hash-values of (blackboard-ks-registry root)
            collect ks))))
