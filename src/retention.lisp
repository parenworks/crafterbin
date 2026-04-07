(in-package #:crafterbin/retention)

;;; ============================================================
;;; Retention curve (mirrors 0x0.st)
;;; ============================================================
;;;
;;; retention = min_age + (max_age - min_age) * pow((1 - file_size/max_size), 3)
;;;
;;; Small files get close to max_age retention.
;;; Files approaching max_size get close to min_age retention.
;;; This uses a cubic decay curve.

(defun compute-retention (file-size)
  "Compute retention duration in seconds based on FILE-SIZE in bytes.
Uses the configured min-age, max-age, and max-size from *config*."
  (let* ((min-age (config-min-age *config*))
         (max-age (config-max-age *config*))
         (max-size (config-max-size *config*))
         (ratio (min 1.0 (/ (coerce file-size 'double-float)
                            (coerce max-size 'double-float))))
         (factor (expt (- 1.0d0 ratio) 3)))
    (floor (+ min-age (* (- max-age min-age) factor)))))

(defun compute-expiry-time (file-size &key expires)
  "Compute the expiry universal-time for a file.
If EXPIRES is provided (seconds from now or absolute universal-time), use that
but cap it at the retention-curve maximum.
Otherwise, use the retention curve based on FILE-SIZE."
  (let* ((now (get-universal-time))
         (curve-retention (compute-retention file-size))
         (curve-expiry (+ now curve-retention)))
    (cond
      ;; No explicit expiry — use the curve
      ((null expires)
       curve-expiry)
      ;; Explicit expiry as hours (small numbers, < 1e9)
      ((< expires 1000000000)
       (let ((requested (+ now (* expires 3600))))
         (min requested curve-expiry)))
      ;; Explicit expiry as milliseconds since UNIX epoch
      (t
       (let* ((unix-seconds (floor expires 1000))
              ;; Convert UNIX epoch to universal time (offset = 2208988800)
              (universal (+ unix-seconds 2208988800)))
         (min universal curve-expiry))))))
