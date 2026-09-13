(in-package #:blackboard-protocol/journal)

;;; Single persistence spine: section writes, KSAR agenda, workspace
;;; fork/merge are task-protocol journal events. Replay rebuilds the board.
;;; No parallel snapshot layer.

(defvar *board-journals* (make-hash-table :test 'eq)
  "Root blackboard → BLACKBOARD-JOURNAL.")

(defvar *replaying-blackboard* nil
  "When T, mutating GFs do not append (replay applies events itself).")

(defvar *replay-apply-agenda* nil
  "When T during replay, ENQUEUE-KSAR is allowed through.")

(defclass blackboard-journal ()
  ((journal :initarg :journal :accessor blackboard-journal-journal)
   (task :initarg :task :accessor blackboard-journal-task)))

(defun blackboard-journal-p (x)
  (typep x 'blackboard-journal))

(defun make-blackboard-journal (&key journal task task-id)
  (let* ((journal (or journal (make-in-memory-journal)))
         (task (or task (make-durable-task
                         :id (or task-id "blackboard")
                         :journal journal))))
    (setf (durable-task-journal task) journal)
    (make-instance 'blackboard-journal :journal journal :task task)))

(defun enable-blackboard-journal (bb journal &key task task-id)
  "Attach JOURNAL as the persistence spine of BB (keyed by the root board)."
  (let* ((root (find-root-bb bb))
         (ctx (if (blackboard-journal-p journal)
                  journal
                  (make-blackboard-journal :journal journal
                                           :task task
                                           :task-id task-id))))
    (setf (gethash root *board-journals*) ctx)
    (let ((*task* (blackboard-journal-task ctx))
          (*journal* (blackboard-journal-journal ctx)))
      (when (eq (durable-task-status (blackboard-journal-task ctx)) :new)
        (task-protocol::%ensure-running (blackboard-journal-task ctx)
                                        (blackboard-journal-journal ctx))))
    ctx))

(defun make-journaled-blackboard (&key journal task task-id (max-concurrency 4))
  (let ((bb (make-blackboard :max-concurrency max-concurrency)))
    (enable-blackboard-journal bb (or journal (make-in-memory-journal))
                               :task task :task-id task-id)
    bb))

(defun board-journal-ctx (bb)
  (gethash (find-root-bb bb) *board-journals*))

(defun board-journal (bb)
  (let ((ctx (board-journal-ctx bb)))
    (and ctx (blackboard-journal-journal ctx))))

(defun board-journal-task (bb)
  (let ((ctx (board-journal-ctx bb)))
    (and ctx (blackboard-journal-task ctx))))

(defun %workspace-name-of (bb)
  (let ((ws (blackboard-protocol::blackboard-owning-workspace bb)))
    (and ws (workspace-name ws))))

(defun %parent-name (parent)
  (cond
    ((null parent) nil)
    ((stringp parent) parent)
    ((typep parent 'workspace) (workspace-name parent))
    (t parent)))

(defun %append-board-step (bb name result)
  (let ((ctx (board-journal-ctx bb)))
    (when (and ctx (not *replaying-blackboard*))
      (let* ((task (blackboard-journal-task ctx))
             (journal (blackboard-journal-journal ctx))
             (*task* task)
             (*journal* journal)
             (event (make-instance 'step-completed
                                   :task-id (durable-task-id task)
                                   :name name
                                   :result (canonicalize-value result)
                                   :idempotency-key
                                   (format nil "~a/~d"
                                           name
                                           (1+ (length (journal-events journal task)))))))
        (append-event journal event)
        (apply-event task event)
        event))))

(defmethod write-section :around ((bb blackboard) key value &key merge-fn)
  (declare (ignore merge-fn))
  (let ((new-val (call-next-method)))
    (%append-board-step bb "write-section"
                        (list :workspace (%workspace-name-of bb)
                              :key key
                              :value new-val))
    new-val))

(defmethod remove-section :around ((bb blackboard) key)
  (prog1 (call-next-method)
    (%append-board-step bb "remove-section"
                        (list :workspace (%workspace-name-of bb)
                              :key key))))

(defmethod enqueue-ksar :around ((bb blackboard) ksar)
  (if (and *replaying-blackboard* (not *replay-apply-agenda*))
      ksar
      (prog1 (call-next-method)
        (%append-board-step (find-root-bb bb) "enqueue-ksar"
                            (list :id (ksar-id ksar)
                                  :watcher-id (ksar-watcher-id ksar)
                                  :workspace (let ((ws (ksar-workspace ksar)))
                                               (and ws (workspace-name ws)))
                                  :triggered-key (ksar-triggered-key ksar)
                                  :priority (ksar-priority ksar)
                                  :status (ksar-status ksar)
                                  :step (ksar-step ksar))))))

(defmethod fork-workspace :around ((bb blackboard) name &key parent max-steps)
  (let ((ws (call-next-method)))
    (%append-board-step (find-root-bb bb) "fork-workspace"
                        (list :name name
                              :parent (%parent-name parent)
                              :max-steps max-steps))
    ws))

(defmethod merge-workspace :around ((ws workspace) &key (strategy :overwrite))
  (let ((root (find-root-bb (workspace-blackboard ws))))
    (prog1 (call-next-method)
      (%append-board-step root "merge-workspace"
                          (list :name (workspace-name ws)
                                :strategy strategy)))))

(defun %target-board (root workspace-name)
  (if workspace-name
      (let ((ws (get-workspace root workspace-name)))
        (unless ws
          (error 'workspace-error
                 :message (format nil "unknown workspace ~s during replay"
                                  workspace-name)))
        (workspace-blackboard ws))
      root))

(defun apply-board-event (board event)
  "Apply one journal EVENT to BOARD. Unknown events are ignored."
  (cond
    ((not (typep event 'step-completed))
     board)
    ((equal (step-name event) "write-section")
     (let* ((r (step-result event))
            (target (%target-board board (getf r :workspace))))
       (write-section target (getf r :key) (getf r :value))
       board))
    ((equal (step-name event) "remove-section")
     (let* ((r (step-result event))
            (target (%target-board board (getf r :workspace))))
       (remove-section target (getf r :key))
       board))
    ((equal (step-name event) "fork-workspace")
     (let ((r (step-result event)))
       (unless (get-workspace board (getf r :name))
         (fork-workspace board (getf r :name)
                         :parent (getf r :parent)
                         :max-steps (getf r :max-steps)))
       board))
    ((equal (step-name event) "merge-workspace")
     (let* ((r (step-result event))
            (ws (get-workspace board (getf r :name))))
       (when (and ws (not (eq (workspace-status ws) :completed)))
         (merge-workspace ws :strategy (or (getf r :strategy) :overwrite)))
       board))
    ((equal (step-name event) "enqueue-ksar")
     (let* ((r (step-result event))
            (ws-name (getf r :workspace))
            (ws (and ws-name (get-workspace board ws-name)))
            (target (or (and ws (workspace-blackboard ws)) board))
            (*replay-apply-agenda* t)
            (ksar (make-ksar :id (getf r :id)
                             :watcher-id (getf r :watcher-id)
                             :workspace ws
                             :blackboard target
                             :triggered-key (getf r :triggered-key)
                             :priority (or (getf r :priority) 0)
                             :status (or (getf r :status) :pending)
                             :step (or (getf r :step) 0))))
       (enqueue-ksar board ksar)
       board))
    (t board)))

(defun replay-blackboard (journal &key blackboard task task-id)
  "Rebuild BOARD (sections + agenda + workspace tree) from JOURNAL.
   TASK defaults to id \"blackboard\"."
  (let* ((*replaying-blackboard* t)
         (task (or task (make-durable-task :id (or task-id "blackboard"))))
         (bb (or blackboard (make-blackboard))))
    (dolist (event (journal-events journal task) bb)
      (apply-board-event bb event))))
