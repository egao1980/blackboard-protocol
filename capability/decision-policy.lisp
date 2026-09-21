(in-package #:capability-protocol)

;;; Invoke-time interceptor that consumes a probability mass, never a
;;; derived "confidence" concentration. Thresholds are p-cuts on a named
;;; outcome key. Journal via ON-DECIDE.

(defun mass-probability (mass key)
  "P(KEY) from MASS (alist). Missing key → 0. Signals if a p is non-finite."
  (check-type mass list)
  (let ((pair (assoc key mass :test #'eql)))
    (unless pair
      (setf pair (assoc key mass :test #'equal)))
    (let ((p (if pair (cdr pair) 0)))
      (unless (and (realp p) (not (complexp p)))
        (error 'capability-error
               :message (format nil "mass probability for ~s is not real: ~s" key p)))
      (float p 1d0))))

(defun %threshold-kind (p deny-at ask-at)
  (cond
    ((and deny-at (>= p deny-at)) :deny)
    ((and ask-at (>= p ask-at)) :ask)
    (t :allow)))

(defclass decision-interceptor (interceptor)
  ((question-id :initarg :question-id :reader decision-interceptor-question-id
                :initform nil)
   (outcome-key :initarg :outcome-key :reader decision-interceptor-outcome-key
                :initform t)
   (lookup :initarg :lookup :reader decision-interceptor-lookup
           :initform nil)
   (deny-at :initarg :deny-at :reader decision-interceptor-deny-at
            :initform nil)
   (ask-at :initarg :ask-at :reader decision-interceptor-ask-at
           :initform nil)
   (on-decide :initarg :on-decide :reader decision-interceptor-on-decide
              :initform nil))
  (:documentation
   "LOOKUP is (lambda invocation) → (values mass model-version).
    Act on P(OUTCOME-KEY): ≥ DENY-AT → :deny, ≥ ASK-AT → :ask, else :allow.
    Concentration / Jev confidence is not an input."))

(defun make-decision-interceptor (&key name question-id (outcome-key t)
                                    lookup deny-at ask-at on-decide)
  (unless (functionp lookup)
    (error 'capability-error :message "decision-interceptor needs :lookup function"))
  (when (and deny-at ask-at (> ask-at deny-at))
    (error 'capability-error
           :message "ASK-AT must be ≤ DENY-AT when both are set"))
  (make-instance 'decision-interceptor
                 :name (or name :decision)
                 :question-id question-id
                 :outcome-key outcome-key
                 :lookup lookup
                 :deny-at deny-at
                 :ask-at ask-at
                 :on-decide on-decide))

(defun %lookup-mass (interceptor invocation)
  (funcall (decision-interceptor-lookup interceptor) invocation))

(defmethod interceptor-pre ((interceptor decision-interceptor) invocation)
  (multiple-value-bind (mass model)
      (%lookup-mass interceptor invocation)
    (let* ((key (decision-interceptor-outcome-key interceptor))
           (p (mass-probability mass key))
           (kind (%threshold-kind p
                                  (decision-interceptor-deny-at interceptor)
                                  (decision-interceptor-ask-at interceptor)))
           (reason (format nil "p(~s)=~,4f question=~s model=~s"
                           key p
                           (decision-interceptor-question-id interceptor)
                           model))
           (decision (make-decision kind :reason reason)))
      (let ((hook (decision-interceptor-on-decide interceptor)))
        (when hook
          (funcall hook :kind kind :mass mass :probability p
                        :model model
                        :question-id (decision-interceptor-question-id interceptor)
                        :outcome-key key
                        :deny-at (decision-interceptor-deny-at interceptor)
                        :ask-at (decision-interceptor-ask-at interceptor)
                        :invocation invocation)))
      decision)))
