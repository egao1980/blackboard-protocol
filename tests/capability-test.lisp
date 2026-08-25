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
    (ok (null (get-capability bb :llm-generation)))))
