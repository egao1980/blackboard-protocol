(in-package #:capability-protocol)

;;; Ordered pre/post interceptors around INVOKE-OPERATION.
;;; Decisions are made outside model context (Semantic Kernel filters /
;;; AgentCore LOG_ONLY → ENFORCE). Trial/tenant policy cannot be bypassed
;;; by constructing a capability elsewhere — this GF is the only public path.

(defvar *policy-chain* nil
  "Dynamically bound POLICY-CHAIN, or NIL for no interceptors.")

(defclass interceptor ()
  ((name :initarg :name :reader interceptor-name :initform nil)))

(defgeneric interceptor-pre (interceptor invocation)
  (:documentation "Return a POLICY-DECISION or NIL (implicit allow).")
  (:method ((interceptor interceptor) invocation)
    (declare (ignore interceptor invocation))
    nil))

(defgeneric interceptor-post (interceptor invocation result)
  (:documentation "Return a POLICY-DECISION or NIL (keep RESULT).")
  (:method ((interceptor interceptor) invocation result)
    (declare (ignore interceptor invocation result))
    nil))

(defclass functional-interceptor (interceptor)
  ((pre :initarg :pre :initform nil)
   (post :initarg :post :initform nil)))

(defmethod interceptor-pre ((interceptor functional-interceptor) invocation)
  (let ((fn (slot-value interceptor 'pre)))
    (when fn (funcall fn invocation))))

(defmethod interceptor-post ((interceptor functional-interceptor) invocation result)
  (let ((fn (slot-value interceptor 'post)))
    (when fn (funcall fn invocation result))))

(defun make-interceptor (&key name pre post)
  (make-instance 'functional-interceptor :name name :pre pre :post post))

(defclass operation-invocation ()
  ((capability :initarg :capability :reader invocation-capability)
   (operation :initarg :operation :reader invocation-operation)
   (args :initarg :args :accessor invocation-args :initform nil)
   (effect-class :initarg :effect-class :reader invocation-effect-class
                 :initform :unknown)
   (decisions :initform nil :accessor invocation-decisions)
   (retry-count :initform 0 :accessor invocation-retry-count)))

(defclass policy-decision ()
  ((kind :initarg :kind :reader decision-kind)
   (reason :initarg :reason :reader decision-reason :initform nil)
   (value :initarg :value :reader decision-value :initform nil)
   (args :initarg :args :reader decision-args :initform nil)
   (interceptor :initarg :interceptor :accessor decision-interceptor
                :initform nil)))

(defun make-decision (kind &key reason value args interceptor)
  (check-type kind (member :allow :deny :ask :transform :redact :retry :cache :audit))
  (make-instance 'policy-decision
                 :kind kind
                 :reason reason
                 :value value
                 :args args
                 :interceptor interceptor))

(defclass policy-chain ()
  ((interceptors :initarg :interceptors :accessor policy-chain-interceptors
                 :initform nil)
   (mode :initarg :mode :accessor policy-chain-mode :initform :enforce)
   (log :initform nil :accessor policy-chain-log)))

(defun make-policy-chain (&key interceptors (mode :enforce))
  (check-type mode (member :log-only :enforce))
  (make-instance 'policy-chain
                 :interceptors (copy-list interceptors)
                 :mode mode))

(defmethod (setf policy-chain-mode) :before (mode (chain policy-chain))
  (declare (ignore chain))
  (check-type mode (member :log-only :enforce)))

(defun add-interceptor (chain interceptor &key (where :append))
  "Register INTERCEPTOR on CHAIN. :APPEND is inner; :PREPEND is outer."
  (check-type chain policy-chain)
  (check-type interceptor interceptor)
  (ecase where
    (:append
     (setf (policy-chain-interceptors chain)
           (append (policy-chain-interceptors chain) (list interceptor))))
    (:prepend
     (push interceptor (policy-chain-interceptors chain))))
  chain)

(defmacro with-policy-chain (chain &body body)
  `(let ((*policy-chain* ,chain))
     ,@body))

(defun %ensure-decision (decision interceptor)
  (when (and decision (null (decision-interceptor decision)))
    (setf (decision-interceptor decision) interceptor))
  decision)

(defun %record-decision (chain invocation decision)
  (push decision (invocation-decisions invocation))
  (push decision (policy-chain-log chain))
  decision)

(defun %signal-denied (invocation decision proceed)
  (restart-case
      (error 'policy-denied
             :invocation invocation
             :decision decision
             :reason (decision-reason decision)
             :message (decision-reason decision))
    (continue ()
      :report "Override the deny and proceed with the operation"
      (funcall proceed))
    (use-value (value)
      :report "Use a supplied result instead of invoking"
      :interactive (lambda ()
                     (format *query-io* "Value to use: ")
                     (force-output *query-io*)
                     (list (read *query-io*)))
      value)))

(defun %signal-ask (invocation decision proceed)
  (restart-case
      (progn
        (signal 'policy-ask
                :invocation invocation
                :decision decision
                :prompt (decision-reason decision))
        ;; Unhandled SIGNAL is not a hard abort — proceed.
        (funcall proceed))
    (continue ()
      :report "Approve the operation"
      (funcall proceed))
    (use-value (value)
      :report "Supply a result without invoking"
      :interactive (lambda ()
                     (format *query-io* "Value to use: ")
                     (force-output *query-io*)
                     (list (read *query-io*)))
      value)
    (decline ()
      :report "Decline the operation"
      (%signal-denied invocation
                      (make-decision :deny
                                     :reason (or (decision-reason decision)
                                                 "declined")
                                     :interceptor (decision-interceptor decision))
                      proceed))))

(defun %apply-decision (chain invocation decision proceed
                        &key (phase :pre) result retry)
  (when (null decision)
    (return-from %apply-decision (funcall proceed)))
  (%record-decision chain invocation decision)
  (ecase (decision-kind decision)
    ((:allow :audit)
     (funcall proceed))
    (:deny
     (if (eq (policy-chain-mode chain) :log-only)
         (funcall proceed)
         (%signal-denied invocation decision proceed)))
    (:ask
     (%signal-ask invocation decision proceed))
    ((:transform :redact)
     (ecase phase
       (:pre
        (when (decision-args decision)
          (setf (invocation-args invocation) (decision-args decision)))
        (funcall proceed))
       (:post (decision-value decision))))
    (:cache
     (if (eq phase :pre)
         (decision-value decision)
         (or (decision-value decision) result)))
    (:retry
     (ecase phase
       (:pre (funcall proceed))
       (:post
        (incf (invocation-retry-count invocation))
        (if (and retry (< (invocation-retry-count invocation) 8))
            (funcall retry)
            result))))))

(defun %run-pre (chain interceptor invocation proceed)
  (let ((raw (interceptor-pre interceptor invocation)))
    (unless (or (null raw) (typep raw 'policy-decision))
      (error 'capability-error
             :message "INTERCEPTOR-PRE must return a POLICY-DECISION or NIL"))
    (%apply-decision chain invocation (%ensure-decision raw interceptor)
                     proceed :phase :pre)))

(defun %run-post (chain interceptor invocation result retry)
  (let ((raw (interceptor-post interceptor invocation result)))
    (unless (or (null raw) (typep raw 'policy-decision))
      (error 'capability-error
             :message "INTERCEPTOR-POST must return a POLICY-DECISION or NIL"))
    (if (null raw)
        result
        (%apply-decision chain invocation (%ensure-decision raw interceptor)
                         (lambda () result)
                         :phase :post :result result :retry retry))))

(defun %invoke-with-chain (chain invocation apply-fn)
  "Onion: pre1 → pre2 → op → post2 → post1. APPLY-FN is the primary method."
  (labels ((run (remaining)
             (if (null remaining)
                 (funcall apply-fn)
                 (let ((interceptor (first remaining))
                       (rest (rest remaining)))
                   (flet ((proceed ()
                            (let ((result (run rest)))
                              (%run-post chain interceptor invocation result
                                         (lambda () (proceed))))))
                     (%run-pre chain interceptor invocation #'proceed))))))
    (run (policy-chain-interceptors chain))))

(defmethod invoke-operation :around ((cap capability) op-name &rest args)
  (let ((chain *policy-chain*))
    (if (null chain)
        (call-next-method)
        (let ((invocation (make-instance 'operation-invocation
                                         :capability cap
                                         :operation op-name
                                         :args args
                                         :effect-class (operation-effect-class cap op-name))))
          (%invoke-with-chain
           chain invocation
           (lambda ()
             (apply #'call-next-method
                    cap
                    op-name
                    (invocation-args invocation))))))))
