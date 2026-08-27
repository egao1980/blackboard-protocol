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

;;; Catalogue = named vocabulary + instance registry.
;;; defcatalogue interned the vocabulary; MAKE-CATALOGUE copies it for live register/get.

(defvar *capability-catalogues* (make-hash-table :test 'eq)
  "defcatalogue specs, keyed by catalogue name (e.g. :llm, :world).")

(defun %make-cap-lock (&optional name)
  "Portable lock: BT2 uses &key NAME; classic BT uses an optional name."
  (handler-case (apply #'bt2:make-lock (and name (list :name name)))
    (error ()
      (if name (bt2:make-lock name) (bt2:make-lock)))))

(defclass capability-catalogue ()
  ((name :initarg :name :reader catalogue-name :initform nil)
   (description :initarg :description :reader catalogue-description :initform "")
   (defined-names :initarg :defined-names :reader catalogue-defined-names
                  :initform nil)
   (entries :initarg :entries :reader catalogue-entries
            :initform (make-hash-table :test 'eq))
   (lock :initarg :lock :reader catalogue-lock
         :initform (%make-cap-lock "capability-catalogue")))
  (:documentation
   "CLOS host for DEFINE (vocabulary in DEFINED-NAMES) and QUERY (ENTRIES).
A blackboard is another host: same GFs, storage stays the shared hash for COW."))

(defun make-capability-catalogue (&key name description defined-names entries lock)
  (make-instance 'capability-catalogue
                 :name name
                 :description (or description "")
                 :defined-names (copy-list defined-names)
                 :entries (or entries (make-hash-table :test 'eq))
                 :lock (or lock (%make-cap-lock "capability-catalogue"))))

(defun find-catalogue (name)
  "Interned defcatalogue spec, or NIL. Do not REGISTER onto this object — MAKE-CATALOGUE."
  (gethash name *capability-catalogues*))

(defun list-catalogues ()
  (let ((out nil))
    (maphash (lambda (k v)
               (declare (ignore k))
               (push v out))
             *capability-catalogues*)
    out))

(defun make-catalogue (name)
  "Live registry with NAME's vocabulary and empty ENTRIES."
  (let ((spec (or (find-catalogue name)
                  (error 'unknown-catalogue :name name))))
    (make-capability-catalogue
     :name (catalogue-name spec)
     :description (catalogue-description spec)
     :defined-names (copy-list (catalogue-defined-names spec)))))

(defun catalogue-defines-p (catalogue name)
  "Is NAME in the catalogue vocabulary (not necessarily registered)?"
  (let ((cat (if (keywordp catalogue)
                 (find-catalogue catalogue)
                 catalogue)))
    (and cat (member name (catalogue-defined-names cat)) t)))

(defun %capability-table (bb)
  (blackboard-protocol::blackboard-capabilities
   (blackboard-protocol:find-root-bb bb)))

(defun %capability-lock (bb)
  (blackboard-protocol::blackboard-lock
   (blackboard-protocol:find-root-bb bb)))

(defgeneric register-capability (host cap)
  (:documentation "Register CAP on HOST (blackboard or capability-catalogue)."))

(defgeneric get-capability (host name)
  (:documentation "Capability instance named NAME on HOST, or NIL."))

(defgeneric unregister-capability (host name))

(defgeneric list-capabilities (host)
  (:documentation "Plists (:name :version :operations) for instances registered on HOST."))

(defgeneric capability-supported-p (host name)
  (:documentation "Is an instance named NAME registered on HOST?")
  (:method (host name)
    (not (null (get-capability host name)))))

(defun %list-from-table (table)
  (let ((result nil))
    (maphash (lambda (name cap)
               (push (list :name name
                           :version (capability-version cap)
                           :operations (mapcar #'capability-operation-name
                                               (capability-operations cap)))
                     result))
             table)
    result))

(defun %interned-catalogue-p (host)
  (let ((spec (and (catalogue-name host) (find-catalogue (catalogue-name host)))))
    (and spec (eq host spec))))

(defun %assert-live-catalogue (host)
  (when (%interned-catalogue-p host)
    (error 'capability-error
           :message (format nil "interned catalogue ~S is read-only — use MAKE-CATALOGUE"
                            (catalogue-name host)))))

(defun %assert-catalogue-defines (host cap)
  (let ((names (catalogue-defined-names host))
        (name (capability-name cap)))
    (when (and names (not (member name names)))
      (error 'unknown-capability :name name))))

(defmethod register-capability ((host capability-catalogue) (cap capability))
  (%assert-live-catalogue host)
  (%assert-catalogue-defines host cap)
  (bt2:with-lock-held ((catalogue-lock host))
    (setf (gethash (capability-name cap) (catalogue-entries host)) cap))
  cap)

(defmethod get-capability ((host capability-catalogue) name)
  (bt2:with-lock-held ((catalogue-lock host))
    (gethash name (catalogue-entries host))))

(defmethod unregister-capability ((host capability-catalogue) name)
  (%assert-live-catalogue host)
  (bt2:with-lock-held ((catalogue-lock host))
    (remhash name (catalogue-entries host))))

(defmethod list-capabilities ((host capability-catalogue))
  (bt2:with-lock-held ((catalogue-lock host))
    (%list-from-table (catalogue-entries host))))

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
      (setf result (%list-from-table (%capability-table bb))))
    result))
