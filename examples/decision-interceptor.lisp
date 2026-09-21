;;;; Offline decision-interceptor demo — p-cuts on mass, never concentration.
;;;;   sbcl --load examples/decision-interceptor.lisp

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package :capability-protocol)
    (require :asdf)
    (asdf:load-system "capability-protocol")))

(defpackage #:capability-protocol/demo
  (:use #:cl #:capability-protocol)
  (:export #:run))

(in-package #:capability-protocol/demo)

(defun run (&optional (stream *standard-output*))
  "Ask-band on p(allow)=4/5. Returns the POLICY-DECISION."
  (let* ((mass '((:allow . 4/5) (:deny . 1/5)))
         (k (length mass))
         (pmax 4/5)
         (conc (/ (- pmax (/ 1 k)) (- 1 (/ 1 k))))
         (journal nil)
         (interceptor (make-decision-interceptor
                       :question-id :risk
                       :outcome-key :allow
                       :deny-at 0.9
                       :ask-at 0.5
                       :lookup (lambda (inv)
                                 (declare (ignore inv))
                                 (values mass "kev-4b"))
                       :on-decide (lambda (&rest args)
                                    (setf journal args))))
         (decision (interceptor-pre interceptor nil)))
    (format stream "~&; p(allow)=~s concentration=~s kind=~s model=~s~%"
            (cdr (assoc :allow mass)) conc
            (decision-kind decision) (getf journal :model))
    (assert (/= conc (cdr (assoc :allow mass))))
    (assert (eq :ask (decision-kind decision)))
    (assert (eq :ask (getf journal :kind)))
    (assert (equal "kev-4b" (getf journal :model)))
    (assert (= (float 4/5 1d0) (getf journal :probability)))
    decision))

#+sbcl
(when (and *load-truename*
           (equal (pathname-name *load-truename*) "decision-interceptor")
           (find "examples/decision-interceptor.lisp" sb-ext:*posix-argv* :test #'search))
  (run)
  (uiop:quit 0))
