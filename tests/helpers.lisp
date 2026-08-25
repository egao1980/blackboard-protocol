(in-package #:blackboard-protocol/tests)

(defun drain (bb &key (timeout 8))
  (run-scheduler bb :until-empty t :timeout timeout)
  bb)

(defun event-log ()
  (list (bt2:make-lock :name "event-log") nil))

(defun log-event (log &rest event)
  (bt2:with-lock-held ((first log))
    (push event (second log))))

(defun events (log)
  (bt2:with-lock-held ((first log))
    (reverse (second log))))

(defun make-barrier (n)
  (list (bt2:make-lock :name "barrier")
        (bt2:make-condition-variable :name "barrier")
        0
        n))

(defun arrive (barrier &key (timeout 5))
  (destructuring-bind (lock cv count target) barrier
    (declare (ignore count))
    (bt2:with-lock-held (lock)
      (incf (third barrier))
      (if (>= (third barrier) target)
          (bt2:condition-broadcast cv)
          (let ((deadline (+ (get-internal-real-time)
                             (* timeout internal-time-units-per-second))))
            (loop while (< (third barrier) target)
                  do (when (>= (get-internal-real-time) deadline)
                       (error "barrier timed out (~D/~D)"
                              (third barrier) target))
                     (bt2:condition-wait cv lock :timeout 0.1)))))))
