(in-package #:blackboard-protocol)

(defun make-bb-lock (&optional name)
  "Portable lock ctor: BT2 uses &key NAME; classic BT uses an optional name."
  (handler-case (apply #'bt2:make-lock (and name (list :name name)))
    (error ()
      (if name (bt2:make-lock name) (bt2:make-lock)))))

(defun make-bb-cv (&optional name)
  "Portable condition-variable ctor."
  (handler-case (apply #'bt2:make-condition-variable (and name (list :name name)))
    (error ()
      (bt2:make-condition-variable))))

(defvar *ksar-counter* 0)

(defclass watcher ()
  ((id :initarg :id :accessor watcher-id)
   (requires :initarg :requires :accessor watcher-requires :initform nil)
   (handler :initarg :handler :accessor watcher-handler :initform nil)
   (priority :initarg :priority :accessor watcher-priority :initform 0)
   (one-shot-p :initarg :one-shot-p :accessor watcher-one-shot-p :initform nil)))

(defclass ksar ()
  ((id :initarg :id :accessor ksar-id)
   (watcher-id :initarg :watcher-id :accessor ksar-watcher-id :initform nil)
   (workspace :initarg :workspace :accessor ksar-workspace :initform nil)
   (blackboard :initarg :blackboard :accessor ksar-blackboard :initform nil)
   (handler :initarg :handler :accessor ksar-handler :initform nil)
   (triggered-key :initarg :triggered-key :accessor ksar-triggered-key :initform nil)
   (priority :initarg :priority :accessor ksar-priority :initform 0)
   (context :initarg :context :accessor ksar-context :initform nil)
   (status :initarg :status :accessor ksar-status :initform :pending)
   (step :initarg :step :accessor ksar-step :initform 0)))

(defun make-ksar (&rest initargs)
  (apply #'make-instance 'ksar
         :id (or (getf initargs :id) (incf *ksar-counter*))
         initargs))

(defstruct pqueue
  (items nil :type list))

(defun pqueue-push (pq ksar)
  "Insert KSAR by descending priority, FIFO tiebreak."
  (let ((pri (ksar-priority ksar)))
    (if (or (null (pqueue-items pq))
            (> pri (ksar-priority (first (pqueue-items pq)))))
        (push ksar (pqueue-items pq))
        (loop for cell on (pqueue-items pq)
              when (or (null (cdr cell))
                       (> pri (ksar-priority (cadr cell))))
                do (setf (cdr cell) (cons ksar (cdr cell)))
                   (return)))))

(defun pqueue-pop (pq)
  (pop (pqueue-items pq)))

(defun pqueue-remove (pq predicate)
  "Remove and return the first item matching PREDICATE, or NIL."
  (let ((items (pqueue-items pq)))
    (cond
      ((null items) nil)
      ((funcall predicate (first items))
       (prog1 (first items)
         (setf (pqueue-items pq) (rest items))))
      (t
       (loop for cell on items
             for next = (cadr cell)
             when (and next (funcall predicate next))
               do (setf (cdr cell) (cddr cell))
                  (return next))))))

(defun pqueue-delete-if (pq predicate)
  (setf (pqueue-items pq) (delete-if predicate (pqueue-items pq))))

(defun pqueue-size (pq)
  (length (pqueue-items pq)))

(defun pqueue-contents (pq)
  (copy-list (pqueue-items pq)))

(defclass blackboard ()
  ((sections :initform (make-hash-table :test 'eq) :reader blackboard-sections)
   (lock :initform (make-bb-lock "blackboard") :reader blackboard-lock)
   (capabilities :initform (make-hash-table :test 'eq) :accessor blackboard-capabilities)
   (workspaces :initform (make-hash-table :test 'equal) :accessor blackboard-workspaces)
   (ks-registry :initform (make-hash-table :test 'equal) :accessor blackboard-ks-registry)
   (watchers :initform (make-hash-table :test 'eq) :accessor bb-watchers)
   (watchers-order :initform nil :accessor bb-watchers-order)
   (watchers-lock :initform (make-bb-lock "bb-watchers") :reader bb-watchers-lock)
   (agenda :initform (make-pqueue) :accessor bb-agenda)
   (agenda-lock :initform (make-bb-lock "bb-agenda") :reader bb-agenda-lock)
   (agenda-cv :initform (make-bb-cv "bb-agenda-cv")
              :reader bb-agenda-cv)
   (scheduler-running :initform nil :accessor scheduler-running-p)
   (scheduler-thread :initform nil :accessor bb-scheduler-thread)
   (max-concurrency :initarg :max-concurrency :initform 4
                    :accessor blackboard-max-concurrency)
   (active-count :initform 0 :accessor bb-active-count)
   (active-lock :initform (make-bb-lock "bb-active") :reader bb-active-lock)
   (active-cv :initform (make-bb-cv "bb-active-cv")
              :reader bb-active-cv)
   (running-workspaces :initform (make-hash-table :test 'eq)
                       :reader bb-running-workspaces)
   (owning-workspace :initform nil :accessor blackboard-owning-workspace)))

(defun make-blackboard (&key (max-concurrency 4))
  (make-instance 'blackboard :max-concurrency max-concurrency))

(defgeneric read-section (bb key &key default))
(defgeneric write-section (bb key value &key merge-fn))
(defgeneric remove-section (bb key))
(defgeneric list-sections (bb))
(defgeneric section-bound-p (bb key))

(defmethod read-section ((bb blackboard) key &key default)
  (bt2:with-lock-held ((blackboard-lock bb))
    (gethash key (blackboard-sections bb) default)))

(defmethod section-bound-p ((bb blackboard) key)
  (bt2:with-lock-held ((blackboard-lock bb))
    (nth-value 1 (gethash key (blackboard-sections bb)))))

(defun %section-bound-unlocked (bb key)
  (nth-value 1 (gethash key (blackboard-sections bb))))

(defmethod write-section ((bb blackboard) key value &key merge-fn)
  (let ((old nil)
        (found nil)
        (new-val nil)
        (changed-p nil))
    (bt2:with-lock-held ((blackboard-lock bb))
      (multiple-value-setq (old found) (gethash key (blackboard-sections bb)))
      (setf new-val (if (and merge-fn found) (funcall merge-fn old value) value)
            changed-p (not (equal old new-val)))
      (setf (gethash key (blackboard-sections bb)) new-val))
    (when changed-p
      (check-watchers-and-enqueue bb key))
    new-val))

(defmethod remove-section ((bb blackboard) key)
  (bt2:with-lock-held ((blackboard-lock bb))
    (remhash key (blackboard-sections bb)))
  key)

(defmethod list-sections ((bb blackboard))
  (bt2:with-lock-held ((blackboard-lock bb))
    (loop for k being the hash-keys of (blackboard-sections bb)
          collect k)))

(defgeneric watch (bb &key id requires handler priority one-shot))
(defgeneric unwatch (bb id))
(defgeneric get-watcher (bb id))
(defgeneric list-watchers (bb))

(defun %make-watcher (&key id requires handler (priority 0) one-shot)
  (make-instance 'watcher :id id :requires requires :handler handler
                          :priority priority :one-shot-p one-shot))

(defun all-requires-present-p (bb requires)
  (every (lambda (key) (section-bound-p bb key)) requires))

(defun snapshot-context (bb requires)
  (loop for key in requires
        collect (cons key (read-section bb key))))

(defun owning-workspace (bb)
  (blackboard-owning-workspace bb))

(defun enqueue-from-watcher (bb w triggered-key)
  (let ((root (find-root-bb bb))
        (ksar (make-ksar :watcher-id (watcher-id w)
                         :workspace (owning-workspace bb)
                         :blackboard bb
                         :handler (watcher-handler w)
                         :triggered-key triggered-key
                         :priority (watcher-priority w)
                         :context (snapshot-context bb (watcher-requires w)))))
    (enqueue-ksar root ksar)
    ksar))

(defmethod watch ((bb blackboard) &key id requires handler (priority 0) one-shot)
  (let ((w (%make-watcher :id id :requires requires :handler handler
                          :priority priority :one-shot one-shot)))
    (bt2:with-lock-held ((bb-watchers-lock bb))
      (unless (gethash id (bb-watchers bb))
        (setf (bb-watchers-order bb)
              (nconc (bb-watchers-order bb) (list id))))
      (setf (gethash id (bb-watchers bb)) w))
    (when (all-requires-present-p bb requires)
      (enqueue-from-watcher bb w :initial)
      (when one-shot
        (unwatch bb id)))
    w))

(defmethod unwatch ((bb blackboard) id)
  (bt2:with-lock-held ((bb-watchers-lock bb))
    (remhash id (bb-watchers bb))
    (setf (bb-watchers-order bb) (delete id (bb-watchers-order bb)))))

(defmethod get-watcher ((bb blackboard) id)
  (bt2:with-lock-held ((bb-watchers-lock bb))
    (gethash id (bb-watchers bb))))

(defmethod list-watchers ((bb blackboard))
  (bt2:with-lock-held ((bb-watchers-lock bb))
    (loop for w being the hash-values of (bb-watchers bb)
          collect w)))

(defun check-watchers-and-enqueue (bb triggered-key)
  (let ((to-fire nil)
        (to-remove nil))
    (bt2:with-lock-held ((bb-watchers-lock bb))
      (dolist (id (copy-list (bb-watchers-order bb)))
        (let ((w (gethash id (bb-watchers bb))))
          (when (and w (member triggered-key (watcher-requires w) :test #'eq)
                     (all-requires-present-p bb (watcher-requires w)))
            (push w to-fire)
            (when (watcher-one-shot-p w)
              (push id to-remove)))))
      (dolist (id to-remove)
        (remhash id (bb-watchers bb))
        (setf (bb-watchers-order bb) (delete id (bb-watchers-order bb)))))
    (dolist (w (nreverse to-fire))
      (enqueue-from-watcher bb w triggered-key))))

(defgeneric find-root-bb (bb)
  (:method ((bb blackboard)) bb))

(defgeneric enqueue-ksar (bb ksar))

(defmethod enqueue-ksar ((bb blackboard) ksar)
  (let ((root (find-root-bb bb)))
    (bt2:with-lock-held ((bb-agenda-lock root))
      (pqueue-push (bb-agenda root) ksar)
      (bt2:condition-notify (bb-agenda-cv root))))
  ksar)

(defun agenda-contents (bb)
  (let ((root (find-root-bb bb)))
    (bt2:with-lock-held ((bb-agenda-lock root))
      (pqueue-contents (bb-agenda root)))))

(defun agenda-size (bb)
  (let ((root (find-root-bb bb)))
    (bt2:with-lock-held ((bb-agenda-lock root))
      (pqueue-size (bb-agenda root)))))

(defun record-bb-error (bb ksar condition)
  (let ((entry (list :time (get-universal-time)
                     :condition (format nil "~A" condition)
                     :type (type-of condition)
                     :ksar-id (and ksar (ksar-id ksar))
                     :watcher-id (and ksar (ksar-watcher-id ksar))))
        (root (find-root-bb bb)))
    (ignore-errors
      (bt2:with-lock-held ((blackboard-lock root))
        (push entry (gethash :errors (blackboard-sections root)))))))
