(in-package #:capability-protocol/tests)

(defclass effect-cap (mock-fs) ())

(defmethod capability-operations ((cap effect-cap))
  (list (make-capability-operation :name 'write-file :effect-class :promotion)
        (make-capability-operation :name 'read-file :effect-class :retrieval)))

(defun %deny-interceptor (&optional (reason "denied"))
  (make-interceptor
   :name :deny
   :pre (lambda (inv)
          (declare (ignore inv))
          (make-decision :deny :reason reason))))

(deftest deny-in-enforce-blocks
  (let* ((chain (make-policy-chain :mode :enforce
                                   :interceptors (list (%deny-interceptor))))
         (cap (make-instance 'mock-fs)))
    (with-policy-chain chain
      (ok (signals (invoke-operation cap 'write-file "a" "b")
                   'policy-denied)))
    (ok (find :deny (policy-chain-log chain) :key #'decision-kind))
    (ok (null (gethash "a" (mock-files cap))))))

(deftest deny-in-log-only-does-not-block
  (let* ((chain (make-policy-chain :mode :log-only
                                   :interceptors (list (%deny-interceptor "would deny"))))
         (cap (make-instance 'mock-fs)))
    (with-policy-chain chain
      (ok (equal "a" (invoke-operation cap 'write-file "a" "secret"))))
    (ok (equal "secret" (gethash "a" (mock-files cap))))
    (ok (find :deny (policy-chain-log chain) :key #'decision-kind))))

(deftest deny-continue-restart
  (let* ((chain (make-policy-chain :interceptors (list (%deny-interceptor))))
         (cap (make-instance 'mock-fs))
         (path (with-policy-chain chain
                 (handler-bind ((policy-denied
                                 (lambda (c)
                                   (declare (ignore c))
                                   (invoke-restart 'continue))))
                   (invoke-operation cap 'write-file "a" "hi")))))
    (ok (equal "a" path))
    (ok (equal "hi" (gethash "a" (mock-files cap))))))

(deftest deny-use-value-restart
  (let* ((chain (make-policy-chain :interceptors (list (%deny-interceptor))))
         (cap (make-instance 'mock-fs))
         (got (with-policy-chain chain
                (handler-bind ((policy-denied
                                (lambda (c)
                                  (use-value :overridden c))))
                  (invoke-operation cap 'write-file "a" "hi")))))
    (ok (eq :overridden got))
    (ok (null (gethash "a" (mock-files cap))))))

(deftest transform-changes-args
  (let* ((i (make-interceptor
             :name :rewrite
             :pre (lambda (inv)
                    (declare (ignore inv))
                    (make-decision :transform
                                   :args '("safe.lisp" "redacted")))))
         (chain (make-policy-chain :interceptors (list i)))
         (cap (make-instance 'mock-fs)))
    (with-policy-chain chain
      (ok (equal "safe.lisp"
                 (invoke-operation cap 'write-file "secret.lisp" "pw"))))
    (ok (equal "redacted" (gethash "safe.lisp" (mock-files cap))))
    (ok (null (gethash "secret.lisp" (mock-files cap))))))

(deftest redact-changes-result
  (let* ((i (make-interceptor
             :name :redact
             :post (lambda (inv result)
                     (declare (ignore inv result))
                     (make-decision :redact :value :redacted))))
         (chain (make-policy-chain :interceptors (list i)))
         (cap (make-instance 'mock-fs)))
    (with-policy-chain chain
      (invoke-operation cap 'write-file "a" "secret")
      (ok (eq :redacted (invoke-operation cap 'read-file "a"))))
    (ok (equal "secret" (gethash "a" (mock-files cap))))))

(deftest interceptor-order-is-onion
  "Registered order is outer→inner: pre1 → pre2 → op → post2 → post1."
  (let* ((trace nil)
         (cap (make-instance 'mock-fs))
         (i1 (make-interceptor
              :name :outer
              :pre (lambda (inv)
                     (declare (ignore inv))
                     (push :pre1 trace)
                     nil)
              :post (lambda (inv result)
                      (declare (ignore inv result))
                      (push :post1 trace)
                      nil)))
         (i2 (make-interceptor
              :name :inner
              :pre (lambda (inv)
                     (declare (ignore inv))
                     (push :pre2 trace)
                     nil)
              :post (lambda (inv result)
                      (declare (ignore inv result))
                      (push :post2 trace)
                      nil)))
         (probe (make-interceptor
                 :name :op-probe
                 :pre (lambda (inv)
                        (declare (ignore inv))
                        (push :op trace)
                        nil)))
         (chain (make-policy-chain :interceptors (list i1 i2 probe))))
    (with-policy-chain chain
      (invoke-operation cap 'write-file "a" "x"))
    (ok (equal '(:pre1 :pre2 :op :post2 :post1) (reverse trace)))))

(deftest invoke-operation-is-only-exported-path
  (let ((extras nil))
    (do-external-symbols (s :capability-protocol)
      (let ((name (symbol-name s)))
        (when (and (search "OPERATION" name)
                   (or (search "APPLY" name)
                       (and (search "INVOKE" name)
                            (not (eq s 'invoke-operation)))))
          (push s extras))))
    (ok (null extras) "no exported apply/invoke bypass of INVOKE-OPERATION")
    (multiple-value-bind (sym status)
        (find-symbol "%INVOKE-WITH-CHAIN" :capability-protocol)
      (ok (not (null sym)))
      (ok (eq :internal status)))))

(deftest constructed-capability-still-hits-chain
  "Invariant: constructing a cap off-board still goes through INVOKE-OPERATION."
  (let* ((seen nil)
         (i (make-interceptor
             :name :audit
             :pre (lambda (inv)
                    (push (list (invocation-operation inv)
                                (invocation-effect-class inv))
                          seen)
                    (make-decision :audit :reason "constructed"))))
         (chain (make-policy-chain :interceptors (list i)))
         (cap (make-instance 'effect-cap)))
    (ok (null (get-capability (make-blackboard) :code-editing)))
    (with-policy-chain chain
      (invoke-operation cap 'write-file "x" "y"))
    (ok (equal '((write-file :promotion)) seen))
    (ok (find :audit (policy-chain-log chain) :key #'decision-kind))))

(deftest unhandled-ask-is-not-a-hard-abort
  (let* ((i (make-interceptor
             :name :ask
             :pre (lambda (inv)
                    (declare (ignore inv))
                    (make-decision :ask :reason "approve?"))))
         (chain (make-policy-chain :interceptors (list i)))
         (cap (make-instance 'mock-fs)))
    (with-policy-chain chain
      (ok (equal "a" (invoke-operation cap 'write-file "a" "ok"))))
    (ok (equal "ok" (gethash "a" (mock-files cap))))
    (ok (find :ask (policy-chain-log chain) :key #'decision-kind))))

(deftest ask-use-value-restart
  (let* ((i (make-interceptor
             :name :ask
             :pre (lambda (inv)
                    (declare (ignore inv))
                    (make-decision :ask :reason "approve?"))))
         (chain (make-policy-chain :interceptors (list i)))
         (cap (make-instance 'mock-fs))
         (got (with-policy-chain chain
                (handler-bind ((policy-ask
                                (lambda (c)
                                  (use-value :approved c))))
                  (invoke-operation cap 'write-file "a" "ok")))))
    (ok (eq :approved got))
    (ok (null (gethash "a" (mock-files cap))))))

(deftest ask-decline-becomes-deny
  (let* ((i (make-interceptor
             :name :ask
             :pre (lambda (inv)
                    (declare (ignore inv))
                    (make-decision :ask :reason "approve?"))))
         (chain (make-policy-chain :interceptors (list i)))
         (cap (make-instance 'mock-fs))
         (blocked nil))
    (handler-case
        (with-policy-chain chain
          (handler-bind ((policy-ask
                          (lambda (c)
                            (invoke-decline c))))
            (invoke-operation cap 'write-file "a" "ok")))
      (policy-denied () (setf blocked t)))
    (ok blocked)
    (ok (null (gethash "a" (mock-files cap))))))

(deftest retry-reinvokes-operation
  (let* ((runs 0)
         (cap (make-instance 'mock-fs))
         (i (make-interceptor
             :name :retry-once
             :post (lambda (inv result)
                     (declare (ignore result))
                     (incf runs)
                     (when (< (invocation-retry-count inv) 1)
                       (make-decision :retry :reason "once")))))
         (chain (make-policy-chain :interceptors (list i))))
    (with-policy-chain chain
      (ok (equal "a" (invoke-operation cap 'write-file "a" "x"))))
    (ok (eql 2 runs))
    (ok (equal "x" (gethash "a" (mock-files cap))))))

(deftest cache-skips-operation
  (let* ((i (make-interceptor
             :name :cache
             :pre (lambda (inv)
                    (declare (ignore inv))
                    (make-decision :cache :value "cached"))))
         (chain (make-policy-chain :interceptors (list i)))
         (cap (make-instance 'mock-fs)))
    (with-policy-chain chain
      (ok (equal "cached" (invoke-operation cap 'read-file "missing"))))
    (ok (null (gethash "missing" (mock-files cap))))))
