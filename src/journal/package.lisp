(defpackage #:blackboard-protocol/journal
  (:use #:cl #:blackboard-protocol #:task-protocol)
  (:export #:blackboard-journal
           #:make-blackboard-journal
           #:blackboard-journal-p
           #:blackboard-journal-journal
           #:blackboard-journal-task
           #:enable-blackboard-journal
           #:journaled-blackboard
           #:make-journaled-blackboard
           #:board-journal
           #:board-journal-task
           #:replay-blackboard
           #:apply-board-event
           #:*replaying-blackboard*))

(in-package #:blackboard-protocol/journal)
