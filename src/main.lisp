(in-package #:crafterbin)

(defun main ()
  "Entry point for CrafterBin."
  (let ((cfg (parse-cli-args)))
    (setf *config* cfg)

    (format *error-output* "~&CrafterBin v~A~%" (asdf:component-version (asdf:find-system :crafterbin)))
    (format *error-output* "~&  Host:     ~A~%" (config-host cfg))
    (format *error-output* "~&  Port:     ~D~%" (config-port cfg))
    (format *error-output* "~&  Storage:  ~A~%" (config-storage-dir cfg))
    (format *error-output* "~&  Min age:  ~D days~%" (floor (config-min-age cfg) (* 24 3600)))
    (format *error-output* "~&  Max age:  ~D days~%" (floor (config-max-age cfg) (* 24 3600)))
    (format *error-output* "~&  Max size: ~A~%"
            (format-size (config-max-size cfg)))
    (when (config-base-url cfg)
      (format *error-output* "~&  Base URL: ~A~%" (config-base-url cfg)))

    ;; Initialize storage
    (crafterbin/storage:init-storage)

    ;; Start cleanup thread
    (start-cleanup-thread)

    ;; Start HTTP server
    (start-server)

    ;; Wait forever (until killed)
    (format *error-output* "~&[main] Ready. Press Ctrl-C to stop.~%")
    (handler-case
        (loop (sleep 3600))
      (sb-sys:interactive-interrupt ()
        (format *error-output* "~&[main] Shutting down...~%")
        (stop-cleanup-thread)
        (stop-server)
        (format *error-output* "~&[main] Goodbye.~%")
        (sb-ext:exit :code 0)))))
