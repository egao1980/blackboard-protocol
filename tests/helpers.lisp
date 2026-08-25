(in-package #:blackboard-protocol/tests)

(defun drain (bb &key (timeout 8))
  (run-scheduler bb :until-empty t :timeout timeout)
  bb)

(defun %test-lock (&optional name)
  (handler-case (apply #'bt2:make-lock (and name (list :name name)))
    (error ()
      (if name (bt2:make-lock name) (bt2:make-lock)))))

(defun %test-cv (&optional name)
  (handler-case (apply #'bt2:make-condition-variable (and name (list :name name)))
    (error ()
      (bt2:make-condition-variable))))

(defun event-log ()
  (list (%test-lock "event-log") nil))

(defun log-event (log &rest event)
  (bt2:with-lock-held ((first log))
    (push event (second log))))

(defun events (log)
  (bt2:with-lock-held ((first log))
    (reverse (second log))))

(defun make-barrier (n)
  (list (%test-lock "barrier")
        (%test-cv "barrier")
        0
        n))

(defun arrive (barrier &key (timeout 5))
  (destructuring-bind (lock cv count target) barrier
    (declare (ignore count))
    (bt2:with-lock-held (lock)
      (incf (third barrier))
      (if (>= (third barrier) target)
          (loop repeat target do (bt2:condition-notify cv))
          (let ((deadline (+ (get-internal-real-time)
                             (* timeout internal-time-units-per-second))))
            (loop while (< (third barrier) target)
                  do (when (>= (get-internal-real-time) deadline)
                       (error "barrier timed out (~D/~D)"
                              (third barrier) target))
                     (bt2:condition-wait cv lock :timeout 0.1)))))))
