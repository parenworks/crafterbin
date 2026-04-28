(in-package #:crafterbin/rate-limit)

;;; ============================================================
;;; Per-IP upload rate limiting
;;; ============================================================

(defvar *window-seconds* 900
  "Rate limit window in seconds (default 15 minutes).")

(defvar *max-requests* 10
  "Maximum uploads per IP within the window.")

(defstruct ip-record
  (count 0 :type fixnum)
  (window-start 0 :type integer))

(defvar *ip-table* (make-hash-table :test #'equal)
  "Hash table mapping IP strings to ip-record structs.")

(defvar *ip-table-lock* (bt:make-lock "rate-limit-lock")
  "Lock for thread-safe access to *ip-table*.")

(defun check-rate-limit (ip)
  "Check whether IP is within its rate limit.
   Returns T if allowed, NIL if rate-limited."
  (bt:with-lock-held (*ip-table-lock*)
    (let* ((now (get-universal-time))
           (record (gethash ip *ip-table*)))
      (cond
        ;; No record yet — create one
        ((null record)
         (setf (gethash ip *ip-table*)
               (make-ip-record :count 1 :window-start now))
         t)
        ;; Window expired — reset
        ((>= (- now (ip-record-window-start record)) *window-seconds*)
         (setf (ip-record-count record) 1
               (ip-record-window-start record) now)
         t)
        ;; Within window and under limit
        ((< (ip-record-count record) *max-requests*)
         (incf (ip-record-count record))
         t)
        ;; Over limit
        (t nil)))))

(defun rate-limit-remaining (ip)
  "Return the number of uploads remaining for IP in the current window."
  (bt:with-lock-held (*ip-table-lock*)
    (let* ((now (get-universal-time))
           (record (gethash ip *ip-table*)))
      (cond
        ((null record) *max-requests*)
        ((>= (- now (ip-record-window-start record)) *window-seconds*)
         *max-requests*)
        (t (max 0 (- *max-requests* (ip-record-count record))))))))

(defun sweep-expired-records ()
  "Remove expired records from the IP table. Called periodically."
  (bt:with-lock-held (*ip-table-lock*)
    (let ((now (get-universal-time))
          (expired nil))
      (maphash (lambda (ip record)
                 (when (>= (- now (ip-record-window-start record)) *window-seconds*)
                   (push ip expired)))
               *ip-table*)
      (dolist (ip expired)
        (remhash ip *ip-table*)))))
