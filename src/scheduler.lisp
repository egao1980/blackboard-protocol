(in-package #:blackboard-protocol)

(defun ksar-serial-key (ksar)
  (or (ksar-workspace ksar) (ksar-blackboard ksar)))

(defun workspace-stopped-p (ws)
  (and ws (member (workspace-status ws) '(:cancelled :discarded :failed))))

(defgeneric requeue-ksar (bb ksar &key workspace))

(defmethod requeue-ksar ((bb blackboard) ksar &key workspace)
  (let* ((ws (or workspace (ksar-workspace ksar)))
         (handler-bb (or (ksar-blackboard ksar) bb))
         (root (find-root-bb bb)))
    (when (workspace-stopped-p ws)
      (return-from requeue-ksar nil))
    (when (and ws (workspace-max-steps ws)
               (>= (workspace-step-count ws) (workspace-max-steps ws)))
      (return-from requeue-ksar nil))
    (enqueue-ksar root
                  (make-ksar :watcher-id (ksar-watcher-id ksar)
                             :workspace ws
                             :blackboard handler-bb
                             :handler (ksar-handler ksar)
                             :triggered-key :requeue
                             :priority (ksar-priority ksar)
                             :context (ksar-context ksar)
                             :step (1+ (or (ksar-step ksar) 0))))))

(defun pop-runnable-ksar (root)
  (bt2:with-lock-held ((bb-agenda-lock root))
    (pqueue-delete-if (bb-agenda root)
                      (lambda (k) (workspace-stopped-p (ksar-workspace k))))
    (when (>= (bb-active-count root) (blackboard-max-concurrency root))
      (return-from pop-runnable-ksar nil))
    (let ((ksar (pqueue-remove
                 (bb-agenda root)
                 (lambda (k)
                   (not (gethash (ksar-serial-key k)
                                 (bb-running-workspaces root)))))))
      (when ksar
        (incf (bb-active-count root))
        (setf (gethash (ksar-serial-key ksar) (bb-running-workspaces root)) t))
      ksar)))

(defun release-ksar-slot (root ksar)
  (bt2:with-lock-held ((bb-agenda-lock root))
    (decf (bb-active-count root))
    (remhash (ksar-serial-key ksar) (bb-running-workspaces root))
    (bt2:condition-notify (bb-agenda-cv root))
    (bt2:condition-notify (bb-active-cv root))))

(defun run-ksar-handler (root ksar)
  (let ((ws (ksar-workspace ksar))
        (board (or (ksar-blackboard ksar) root))
        (handler (ksar-handler ksar)))
    (when (workspace-stopped-p ws)
      (setf (ksar-status ksar) :failed)
      (return-from run-ksar-handler nil))
    (when ws
      (incf (workspace-step-count ws)))
    (handler-case
        (progn
          (setf (ksar-status ksar) :running)
          (when handler
            (funcall handler board ksar))
          (setf (ksar-status ksar) :completed))
      (serious-condition (e)
        (setf (ksar-status ksar) :failed)
        (record-bb-error root ksar e)))))

(defun spawn-ksar-worker (root ksar)
  (bt2:make-thread
   (lambda ()
     (unwind-protect
          (run-ksar-handler root ksar)
       (release-ksar-slot root ksar)))
   :name (format nil "ksar-~A" (ksar-id ksar))))

(defun drain-agenda (root &key (timeout 10))
  (let ((deadline (+ (get-internal-real-time)
                     (* timeout internal-time-units-per-second)))
        (workers nil))
    (unwind-protect
         (loop
           (when (>= (get-internal-real-time) deadline)
             (error 'scheduler-timeout
                    :message (format nil "agenda=~A active=~A"
                                     (agenda-size root)
                                     (bb-active-count root))))
           (let ((dispatched 0))
             (loop for ksar = (pop-runnable-ksar root)
                   while ksar
                   do (incf dispatched)
                      (push (spawn-ksar-worker root ksar) workers))
             (bt2:with-lock-held ((bb-agenda-lock root))
               (cond
                 ((plusp (bb-active-count root))
                  (bt2:condition-wait (bb-active-cv root)
                                      (bb-agenda-lock root)
                                      :timeout 0.1))
                 ((plusp (pqueue-size (bb-agenda root)))
                  nil)
                 ((zerop dispatched)
                  (return))))))
      (dolist (th workers)
        (when (bt2:thread-alive-p th)
          (ignore-errors (bt2:join-thread th)))))))

(defun start-scheduler (bb)
  (let ((root (find-root-bb bb)))
    (when (scheduler-running-p root)
      (return-from start-scheduler root))
    (setf (scheduler-running-p root) t)
    (setf (bb-scheduler-thread root)
          (bt2:make-thread
           (lambda ()
             (loop while (scheduler-running-p root) do
               (handler-case
                   (let ((ksar (pop-runnable-ksar root)))
                     (if ksar
                         (spawn-ksar-worker root ksar)
                         (bt2:with-lock-held ((bb-agenda-lock root))
                           (unless (scheduler-running-p root)
                             (return))
                           (bt2:condition-wait (bb-agenda-cv root)
                                               (bb-agenda-lock root)
                                               :timeout 0.25))))
                 (serious-condition (e)
                   (record-bb-error root nil e)
                   (sleep 0.2)))))
           :name "bb-scheduler"))
    root))

(defun stop-scheduler (bb &key (wait-seconds 10))
  (let ((root (find-root-bb bb)))
    (setf (scheduler-running-p root) nil)
    (bt2:with-lock-held ((bb-agenda-lock root))
      (bt2:condition-notify (bb-agenda-cv root)))
    (let ((thread (bb-scheduler-thread root)))
      (when (and thread (bt2:thread-alive-p thread))
        (let ((deadline (+ (get-internal-real-time)
                           (* wait-seconds internal-time-units-per-second))))
          (loop while (and (bt2:thread-alive-p thread)
                           (< (get-internal-real-time) deadline))
                do (sleep 0.05))
          (ignore-errors (bt2:join-thread thread))))
      (setf (bb-scheduler-thread root) nil))
    root))

(defun wait-until-idle (bb &key (timeout 10))
  (let ((root (find-root-bb bb))
        (deadline (+ (get-internal-real-time)
                     (* timeout internal-time-units-per-second))))
    (loop
      (when (bt2:with-lock-held ((bb-agenda-lock root))
              (and (zerop (pqueue-size (bb-agenda root)))
                   (zerop (bb-active-count root))))
        (return root))
      (when (>= (get-internal-real-time) deadline)
        (error 'scheduler-timeout :message "wait-until-idle"))
      (sleep 0.02))))

(defgeneric run-scheduler (bb &key until-empty timeout))

(defmethod run-scheduler ((bb blackboard) &key until-empty timeout)
  (let ((root (find-root-bb bb)))
    (if until-empty
        (drain-agenda root :timeout (or timeout 10))
        (start-scheduler root))
    root))
