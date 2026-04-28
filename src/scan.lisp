(in-package #:crafterbin/scan)

;;; ============================================================
;;; ClamAV integration via clamdscan
;;; ============================================================

(defvar *clamdscan-path* "/usr/bin/clamdscan"
  "Path to the clamdscan binary.")

(define-condition virus-detected (error)
  ((path :initarg :path :reader virus-path)
   (signature :initarg :signature :reader virus-signature))
  (:report (lambda (c s)
             (format s "Virus detected in ~A: ~A"
                     (virus-path c) (virus-signature c)))))

(defun scan-file (path)
  "Scan a file using ClamAV daemon. Returns T if clean.
   Signals VIRUS-DETECTED if infected.
   Signals an error if clamdscan is unavailable or fails."
  (let ((pathstr (namestring (truename path))))
    ;; clamdscan exit codes:
    ;;   0 = clean
    ;;   1 = virus found
    ;;   2 = error
    (multiple-value-bind (stdout stderr exit-code)
        (uiop:run-program
         (list *clamdscan-path* "--no-summary" pathstr)
         :output :string
         :error-output :string
         :ignore-error-status t)
      (declare (ignore stderr))
      (case exit-code
        (0 t)
        (1
         (let* ((trimmed (string-trim '(#\Space #\Newline #\Return) stdout))
                ;; Output format: "/path/to/file: SigName FOUND"
                (found-pos (search " FOUND" trimmed))
                (colon-pos (position #\: trimmed))
                (signature (if (and colon-pos found-pos)
                               (string-trim '(#\Space)
                                            (subseq trimmed (1+ colon-pos) found-pos))
                               "unknown")))
           (error 'virus-detected :path pathstr :signature signature)))
        (otherwise
         (error "ClamAV scan failed (exit ~D): ~A" exit-code stdout))))))
