(in-package #:capability-protocol)

(defun parse-operation (op-form)
  (destructuring-bind (op-tag op-name params &key returns (doc "")
                               (effect-class :unknown))
      op-form
    (declare (ignore op-tag))
    (let ((clean-params (remove-if (lambda (p)
                                     (and (symbolp p)
                                          (string= "&KEY" (symbol-name p))))
                                   params)))
      (values op-name clean-params returns doc effect-class))))

(defmacro defcapability (name doc &body operations)
  "Define a capability class and operation generic functions.
NAME is a keyword. OPERATIONS: (:operation op-name (params...) &key returns doc effect-class)."
  (let* ((class-name (intern (format nil "~A-CAPABILITY"
                                    (string-upcase (symbol-name name)))))
         (gen-forms nil)
         (desc-forms nil))
    (dolist (op operations)
      (multiple-value-bind (op-name params returns op-doc effect-class)
          (parse-operation op)
        (let ((param-names (mapcar (lambda (p) (if (listp p) (car p) p)) params)))
          (push `(defgeneric ,op-name (cap ,@param-names &key)
                   (:documentation ,op-doc))
                gen-forms)
          (push `(make-capability-operation
                  :name ',op-name
                  :params ',params
                  :returns ',returns
                  :doc ,op-doc
                  :effect-class ,effect-class)
                desc-forms))))
    `(progn
       (defclass ,class-name (capability)
         ()
         (:default-initargs :name ,name :description ,doc))
       (defmethod capability-operations ((cap ,class-name))
         (list ,@(nreverse desc-forms)))
       ,@(nreverse gen-forms)
       ',class-name)))

(defmacro defcatalogue (name doc &body capability-names)
  "Intern a named capability vocabulary. Query with FIND-CATALOGUE / CATALOGUE-DEFINES-P.
Live register/get uses (MAKE-CATALOGUE NAME), not the interned spec."
  `(progn
     (setf (gethash ,name *capability-catalogues*)
           (make-capability-catalogue
            :name ,name
            :description ,doc
            :defined-names ',capability-names))
     ',name))
