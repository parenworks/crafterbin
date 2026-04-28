(in-package #:crafterbin/cleanup)

;;; ============================================================
;;; Background cleanup thread
;;; ============================================================

(defvar *cleanup-thread* nil "The background cleanup thread.")
(defvar *cleanup-running* nil "Flag to stop the cleanup loop.")

(defun run-cleanup ()
  "Sweep expired files once."
  (let ((expired (list-expired-entries)))
    (when expired
      (format *error-output* "~&[cleanup] Removing ~D expired file~:P~%" (length expired))
      (dolist (id expired)
        (handler-case
            (progn
              (delete-entry id)
              (format *error-output* "~&[cleanup] Deleted ~A~%" id))
          (error (e)
            (format *error-output* "~&[cleanup] Error deleting ~A: ~A~%" id e)))))))

(defun cleanup-loop ()
  "Main loop for the cleanup thread."
  (loop while *cleanup-running*
        do (handler-case (run-cleanup)
             (error (e)
               (format *error-output* "~&[cleanup] Sweep error: ~A~%" e)))
           (handler-case (sweep-expired-records)
             (error (e)
               (format *error-output* "~&[cleanup] Rate-limit sweep error: ~A~%" e)))
           (sleep (config-cleanup-interval *config*))))

(defun start-cleanup-thread ()
  "Start the background cleanup thread."
  (setf *cleanup-running* t)
  (setf *cleanup-thread*
        (bt:make-thread #'cleanup-loop :name "crafterbin-cleanup"))
  (format *error-output* "~&[cleanup] Started (interval: ~Ds)~%"
          (config-cleanup-interval *config*)))

(defun stop-cleanup-thread ()
  "Stop the background cleanup thread."
  (setf *cleanup-running* nil)
  (when (and *cleanup-thread* (bt:thread-alive-p *cleanup-thread*))
    (bt:destroy-thread *cleanup-thread*)
    (setf *cleanup-thread* nil))
  (format *error-output* "~&[cleanup] Stopped~%"))
