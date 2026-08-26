(in-package #:capability-protocol/tests)

(deftest defcapability-and-portable-invoke
  (let ((cap (make-instance 'code-editing-capability)))
    (ok (eq :code-editing (capability-name cap)))
    (ok (find 'write-file (capability-operations cap)
              :key #'capability-operation-name))
    (ok (signals (invoke-operation cap 'no-such-op)
                 'unknown-operation))))

(defclass mock-fs (code-editing-capability)
  ((files :initform (make-hash-table :test 'equal) :accessor mock-files)))

(defmethod read-file ((cap mock-fs) path &key)
  (or (gethash path (mock-files cap))
      (error "missing ~A" path)))

(defmethod write-file ((cap mock-fs) path content &key)
  (setf (gethash path (mock-files cap)) content)
  path)

(deftest invoke-operation-dispatches-gf
  (let ((cap (make-instance 'mock-fs)))
    (invoke-operation cap 'write-file "a.lisp" "(+ 1 2)")
    (ok (equal "(+ 1 2)" (invoke-operation cap 'read-file "a.lisp")))
    (ok (equal "(+ 1 2)" (read-file cap "a.lisp")))))

(deftest register-capability-on-board
  (let ((bb (make-blackboard))
        (cap (make-instance 'mock-fs)))
    (register-capability bb cap)
    (ok (eq cap (get-capability bb :code-editing)))
    (ok (member :code-editing (mapcar (lambda (row) (getf row :name))
                                      (list-capabilities bb))))
    (unregister-capability bb :code-editing)
    (ok (signals (progn
                   (or (get-capability bb :code-editing)
                       (error 'unknown-capability :name :code-editing)))
                 'unknown-capability))))

(deftest invoke-unknown-capability
  (let ((bb (make-blackboard)))
    (ok (null (get-capability bb :llm-generation)))
    (ng (capability-supported-p bb :llm-generation))))

(deftest require-capability-use-value
  (let ((bb (make-blackboard))
        (cap (make-instance 'code-editing-capability)))
    (ok (eq cap
            (handler-bind ((unknown-capability
                            (lambda (c)
                              (invoke-use-value cap c))))
              (require-capability bb :code-editing))))))

(deftest catalogues-define-and-query
  (ok (catalogue-defines-p :llm :llm-vision))
  (ok (catalogue-defines-p :llm :llm-generation))
  (ok (catalogue-defines-p :world :compute))
  (ng (catalogue-defines-p :llm :compute))
  (ng (catalogue-defines-p :world :llm-vision))
  (ok (find-catalogue :llm))
  (ok (eq :llm (catalogue-name (find-catalogue :llm))))
  (ok (signals (make-catalogue :no-such-catalogue) 'unknown-catalogue))
  (let ((cat (make-catalogue :llm))
        (cap (make-instance 'llm-vision-capability)))
    (ng (capability-supported-p cat :llm-vision))
    (register-capability cat cap)
    (ok (capability-supported-p cat :llm-vision))
    (ok (eq cap (get-capability cat :llm-vision)))
    (ok (member :llm-vision (mapcar (lambda (row) (getf row :name))
                                    (list-capabilities cat))))
    (unregister-capability cat :llm-vision)
    (ng (capability-supported-p cat :llm-vision))))

(deftest make-catalogue-does-not-share-interned-entries
  (let ((spec (find-catalogue :llm))
        (live (make-catalogue :llm)))
    (register-capability live (make-instance 'llm-generation-capability))
    (ok (capability-supported-p live :llm-generation))
    (ng (capability-supported-p spec :llm-generation))))

(deftest interned-catalogue-is-read-only
  (let ((spec (find-catalogue :llm)))
    (ok (signals (register-capability spec (make-instance 'llm-generation-capability))
                 'capability-error))
    (ok (signals (unregister-capability spec :llm-generation)
                 'capability-error))))

(deftest catalogue-rejects-undefined-name
  (let ((cat (make-catalogue :llm)))
    (ok (signals (register-capability cat (make-instance 'compute-capability))
                 'unknown-capability))))
