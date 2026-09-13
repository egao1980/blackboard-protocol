(in-package #:blackboard-protocol/tests)

(defun %section-alist (bb)
  (sort (mapcar (lambda (k) (cons k (read-section bb k)))
                (list-sections bb))
        #'string< :key (lambda (p) (string (car p)))))

(defun %workspace-names (bb)
  (sort (mapcar #'workspace-name (list-workspaces bb)) #'string<))

(deftest journal-write-fork-merge-replay
  (let* ((journal (task-protocol:make-in-memory-journal))
         (bb (blackboard-protocol/journal:make-journaled-blackboard
              :journal journal :task-id "board-1")))
    (write-section bb :a 1)
    (write-section bb :b "keep")
    (let ((ws (fork-workspace bb "child")))
      (write-section (workspace-blackboard ws) :a 9)
      (write-section (workspace-blackboard ws) :c 3)
      (merge-workspace ws :strategy :overwrite))
    (ok (eql 9 (read-section bb :a)))
    (ok (equal "keep" (read-section bb :b)))
    (ok (eql 3 (read-section bb :c)))
    (let* ((fresh (make-blackboard))
           (replayed (blackboard-protocol/journal:replay-blackboard
                      journal :blackboard fresh :task-id "board-1")))
      (ok (equal (%section-alist bb) (%section-alist replayed)))
      (ok (equal (%workspace-names bb) (%workspace-names replayed)))
      (ok (eq :completed
              (workspace-status (get-workspace replayed "child")))))))

(deftest-parametrize journal-merge-strategy-replay
    ((strategy expected-a expected-c)
     (:overwrite 9 3)
     (:union 1 3))
  (let* ((journal (task-protocol:make-in-memory-journal))
         (bb (blackboard-protocol/journal:make-journaled-blackboard
              :journal journal :task-id "board-merge")))
    (write-section bb :a 1)
    (let ((ws (fork-workspace bb "child")))
      (write-section (workspace-blackboard ws) :a 9)
      (write-section (workspace-blackboard ws) :c 3)
      (merge-workspace ws :strategy strategy))
    (ok (eql expected-a (read-section bb :a)))
    (ok (eql expected-c (read-section bb :c)))
    (let ((replayed (blackboard-protocol/journal:replay-blackboard
                     (task-protocol:copy-in-memory-journal journal)
                     :task-id "board-merge")))
      (ok (equal (%section-alist bb) (%section-alist replayed))))))

(deftest journal-remove-section-replay
  (let* ((journal (task-protocol:make-in-memory-journal))
         (bb (blackboard-protocol/journal:make-journaled-blackboard
              :journal journal)))
    (write-section bb :keep 1)
    (write-section bb :drop 2)
    (remove-section bb :drop)
    (let ((replayed (blackboard-protocol/journal:replay-blackboard journal)))
      (ok (equal (%section-alist bb) (%section-alist replayed)))
      (ng (section-bound-p replayed :drop)))))

(deftest journal-agenda-enqueue-replay
  (let* ((journal (task-protocol:make-in-memory-journal))
         (bb (blackboard-protocol/journal:make-journaled-blackboard
              :journal journal :task-id "agenda"))
         (ksar (make-ksar :watcher-id 'echo :priority 3 :triggered-key :ping)))
    (write-section bb :ping 1)
    (enqueue-ksar bb ksar)
    (ok (= 1 (agenda-size bb)))
    (let ((replayed (blackboard-protocol/journal:replay-blackboard
                     journal :task-id "agenda")))
      (ok (equal (%section-alist bb) (%section-alist replayed)))
      (ok (= 1 (agenda-size replayed)))
      (ok (eql 3 (ksar-priority (first (agenda-contents replayed))))))))
