(defpackage #:crafterbin/config
  (:use #:cl)
  (:export #:*config*
           #:config
           #:config-host
           #:config-port
           #:config-storage-dir
           #:config-min-age
           #:config-max-age
           #:config-max-size
           #:config-cleanup-interval
           #:config-base-url
           #:parse-cli-args
           #:make-default-config))

(defpackage #:crafterbin/storage
  (:use #:cl #:crafterbin/config)
  (:export #:file-entry
           #:entry-id
           #:entry-filename
           #:entry-content-type
           #:entry-size
           #:entry-token
           #:entry-ip
           #:entry-user-agent
           #:entry-created-at
           #:entry-expires-at
           #:entry-secret-p
           #:init-storage
           #:store-upload
           #:store-from-url
           #:lookup-entry
           #:delete-entry
           #:update-entry-expiry
           #:list-expired-entries
           #:file-data-path
           #:generate-id
           #:generate-token
           #:serialize-meta
           #:deserialize-meta))

(defpackage #:crafterbin/retention
  (:use #:cl #:crafterbin/config)
  (:export #:compute-retention
           #:compute-expiry-time))

(defpackage #:crafterbin/scan
  (:use #:cl)
  (:export #:scan-file
           #:virus-detected
           #:virus-signature
           #:*clamdscan-path*))

(defpackage #:crafterbin/rate-limit
  (:use #:cl)
  (:nicknames #:crafterbin/rl)
  (:export #:check-rate-limit
           #:rate-limit-remaining
           #:sweep-expired-records
           #:*window-seconds*
           #:*max-requests*))

(defpackage #:crafterbin/cleanup
  (:use #:cl #:crafterbin/config #:crafterbin/storage #:crafterbin/rate-limit)
  (:export #:start-cleanup-thread
           #:stop-cleanup-thread))

(defpackage #:crafterbin/server
  (:use #:cl #:crafterbin/config #:crafterbin/storage
        #:crafterbin/retention #:crafterbin/scan #:crafterbin/rate-limit)
  (:export #:start-server
           #:stop-server
           #:format-size))

(defpackage #:crafterbin
  (:use #:cl #:crafterbin/config #:crafterbin/server
        #:crafterbin/cleanup #:crafterbin/storage)
  (:export #:main))
