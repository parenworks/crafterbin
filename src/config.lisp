(in-package #:crafterbin/config)

(defclass config ()
  ((host :initarg :host :accessor config-host :initform "127.0.0.1")
   (port :initarg :port :accessor config-port :initform 8080)
   (storage-dir :initarg :storage-dir :accessor config-storage-dir
                :initform "/mnt/crafterbin/storage")
   (min-age :initarg :min-age :accessor config-min-age
            :initform (* 7 24 3600)
            :documentation "Minimum retention in seconds (default 7 days)")
   (max-age :initarg :max-age :accessor config-max-age
            :initform (* 365 24 3600)
            :documentation "Maximum retention in seconds (default 365 days)")
   (max-size :initarg :max-size :accessor config-max-size
             :initform (* 512 1024 1024)
             :documentation "Maximum upload size in bytes (default 512 MiB)")
   (cleanup-interval :initarg :cleanup-interval :accessor config-cleanup-interval
                     :initform 60
                     :documentation "Seconds between cleanup sweeps (default 60)")
   (base-url :initarg :base-url :accessor config-base-url
             :initform nil
             :documentation "Public base URL (e.g. https://crafterbin.glennstack.dev)"))
  (:documentation "Runtime configuration for CrafterBin."))

(defvar *config* nil "Active configuration instance.")

(defun make-default-config ()
  (make-instance 'config))

(opts:define-opts
  (:name :host
   :description "Bind address"
   :short #\H
   :long "host"
   :arg-parser #'identity
   :meta-var "ADDR")
  (:name :port
   :description "Listen port"
   :short #\P
   :long "port"
   :arg-parser #'parse-integer
   :meta-var "PORT")
  (:name :storage
   :description "Storage directory path"
   :short #\s
   :long "storage"
   :arg-parser #'identity
   :meta-var "DIR")
  (:name :min-age
   :description "Minimum file retention in days (default 7)"
   :long "min-age"
   :arg-parser #'parse-integer
   :meta-var "DAYS")
  (:name :max-age
   :description "Maximum file retention in days (default 365)"
   :long "max-age"
   :arg-parser #'parse-integer
   :meta-var "DAYS")
  (:name :max-size
   :description "Maximum upload size in MiB (default 512)"
   :long "max-size"
   :arg-parser #'parse-integer
   :meta-var "MIB")
  (:name :cleanup-interval
   :description "Cleanup sweep interval in seconds (default 60)"
   :long "cleanup-interval"
   :arg-parser #'parse-integer
   :meta-var "SECS")
  (:name :base-url
   :description "Public base URL for generated links"
   :long "base-url"
   :arg-parser #'identity
   :meta-var "URL")
  (:name :help
   :description "Show this help"
   :short #\h
   :long "help"))

(defun parse-cli-args ()
  "Parse command-line arguments and return a config instance."
  (multiple-value-bind (options) (opts:get-opts)
    (when (getf options :help)
      (opts:describe
       :prefix "CrafterBin — temporary file sharing service"
       :args "[options]")
      (sb-ext:exit :code 0))
    (let ((cfg (make-default-config)))
      (when (getf options :host)
        (setf (config-host cfg) (getf options :host)))
      (when (getf options :port)
        (setf (config-port cfg) (getf options :port)))
      (when (getf options :storage)
        (setf (config-storage-dir cfg) (getf options :storage)))
      (when (getf options :min-age)
        (setf (config-min-age cfg) (* (getf options :min-age) 24 3600)))
      (when (getf options :max-age)
        (setf (config-max-age cfg) (* (getf options :max-age) 24 3600)))
      (when (getf options :max-size)
        (setf (config-max-size cfg) (* (getf options :max-size) 1024 1024)))
      (when (getf options :cleanup-interval)
        (setf (config-cleanup-interval cfg) (getf options :cleanup-interval)))
      (when (getf options :base-url)
        (setf (config-base-url cfg) (getf options :base-url)))
      cfg)))
