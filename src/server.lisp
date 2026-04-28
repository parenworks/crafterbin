(in-package #:crafterbin/server)

;;; ============================================================
;;; HTTP Server
;;; ============================================================

(defvar *acceptor* nil "The Hunchentoot acceptor instance.")

;;; ============================================================
;;; Helpers
;;; ============================================================

(defun client-ip ()
  "Get the client IP, respecting X-Forwarded-For for reverse proxies."
  (or (hunchentoot:header-in* :x-forwarded-for)
      (hunchentoot:real-remote-addr)))

(defun client-ua ()
  "Get the client User-Agent."
  (or (hunchentoot:header-in* :user-agent) ""))

(defun file-url (entry)
  "Construct the public URL for a file entry."
  (let ((base (or (config-base-url *config*)
                  (format nil "http://~A:~A"
                          (config-host *config*)
                          (config-port *config*)))))
    (format nil "~A/~A" (string-right-trim "/" base) (entry-id entry))))

(defun format-size (bytes)
  "Format a byte count as a human-readable string."
  (cond ((>= bytes (* 1024 1024 1024))
         (format nil "~,1f GiB" (/ bytes (* 1024.0 1024 1024))))
        ((>= bytes (* 1024 1024))
         (format nil "~,1f MiB" (/ bytes (* 1024.0 1024))))
        ((>= bytes 1024)
         (format nil "~,1f KiB" (/ bytes 1024.0)))
        (t (format nil "~D B" bytes))))

;;; ============================================================
;;; Landing page
;;; ============================================================

(defun landing-page ()
  "Generate the plaintext landing page."
  (format nil "CRAFTERBIN
==========
Temporary file sharing service.

min_age  = ~D days
max_age  = ~D days
max_size = ~A

retention = min_age + (max_age - min_age) * pow((1 - file_size / max_size), 3)

Uploading files
---------------
Send HTTP POST requests with data encoded as multipart/form-data.

  field    | content     | remarks
  ---------+-------------+-----------------------------------------------
  file     | data        |
  url      | remote URL  | Mutually exclusive with \"file\".
  secret   | (ignored)   | If present, generates a longer, hard-to-guess URL.
  expires  | hours OR    | Sets maximum lifetime in hours OR expiration
           | ms epoch    | as milliseconds since UNIX epoch.

cURL examples
-------------
  Upload a file:
    curl -F'file=@yourfile.png' ~A

  Copy from URL:
    curl -F'url=http://example.com/image.jpg' ~A

  Secret URL:
    curl -F'file=@yourfile.png' -Fsecret= ~A

  Set expiry (24 hours):
    curl -F'file=@yourfile.png' -Fexpires=24 ~A

Managing files
--------------
  The X-Token response header contains a management token.
  Use -i with cURL to see it.

  Delete a file:
    curl -Ftoken=TOKEN -Fdelete= ~A/ID

  Update expiry:
    curl -Ftoken=TOKEN -Fexpires=72 ~A/ID

Powered by CrafterBin (Common Lisp)
"
          (floor (config-min-age *config*) (* 24 3600))
          (floor (config-max-age *config*) (* 24 3600))
          (format-size (config-max-size *config*))
          ;; URL placeholders
          (or (config-base-url *config*) "THIS_URL")
          (or (config-base-url *config*) "THIS_URL")
          (or (config-base-url *config*) "THIS_URL")
          (or (config-base-url *config*) "THIS_URL")
          (or (config-base-url *config*) "THIS_URL")
          (or (config-base-url *config*) "THIS_URL")))

;;; ============================================================
;;; Handlers
;;; ============================================================

(defun handle-upload ()
  "Handle POST to / - file upload or URL fetch."
  (let* ((file-param (hunchentoot:post-parameter "file"))
         (url-param (hunchentoot:post-parameter "url"))
         (secret-param (hunchentoot:post-parameter "secret"))
         (expires-param (hunchentoot:post-parameter "expires"))
         (secret-p (not (null secret-param)))
         (expires (when (and expires-param (plusp (length expires-param)))
                   (parse-integer expires-param :junk-allowed t))))
    (cond
      ;; File upload
      ((and file-param (listp file-param))
       (destructuring-bind (tmp-path original-name content-type) file-param
         (let ((size (with-open-file (f tmp-path) (file-length f))))
           ;; Size check
           (when (> size (config-max-size *config*))
             (setf (hunchentoot:return-code*) 413)
             (return-from handle-upload
               (format nil "Error: file too large (~A, max ~A)~%"
                       (format-size size) (format-size (config-max-size *config*)))))
           ;; ClamAV scan
           (handler-case (scan-file tmp-path)
             (virus-detected (v)
               (setf (hunchentoot:return-code*) 403)
               (return-from handle-upload
                 (format nil "Error: virus detected (~A)~%" (virus-signature v)))))
           (let* ((expiry (compute-expiry-time size :expires expires))
                  (entry (with-open-file (in tmp-path :element-type '(unsigned-byte 8))
                           (store-upload in original-name content-type size expiry
                                         :ip (client-ip)
                                         :user-agent (client-ua)
                                         :secret-p secret-p))))
             ;; Set management token header
             (setf (hunchentoot:header-out :x-token) (entry-token entry))
             (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
             (format nil "~A~%" (file-url entry))))))

      ;; URL fetch
      ((and url-param (plusp (length url-param)))
       (handler-case
           (let* ((expiry-default (compute-expiry-time 0 :expires expires))
                  (entry (store-from-url url-param expiry-default
                                         :ip (client-ip)
                                         :user-agent (client-ua)
                                         :secret-p secret-p)))
             ;; ClamAV scan the stored file
             (handler-case (scan-file (file-data-path (entry-id entry)))
               (virus-detected (v)
                 (delete-entry (entry-id entry))
                 (setf (hunchentoot:return-code*) 403)
                 (return-from handle-upload
                   (format nil "Error: virus detected (~A)~%" (virus-signature v)))))
             ;; Recompute expiry with actual size
             (let ((real-expiry (compute-expiry-time (entry-size entry) :expires expires)))
               (unless (= real-expiry (entry-expires-at entry))
                 (update-entry-expiry (entry-id entry) real-expiry)))
             (setf (hunchentoot:header-out :x-token) (entry-token entry))
             (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
             (format nil "~A~%" (file-url entry)))
         (error (e)
           (setf (hunchentoot:return-code*) 400)
           (format nil "Error fetching URL: ~A~%" e))))

      ;; Nothing provided
      (t
       (setf (hunchentoot:return-code*) 400)
       (format nil "Error: no file or URL provided~%")))))

(defun handle-manage (id)
  "Handle POST to /<id> - delete or update expiry."
  (let* ((token (hunchentoot:post-parameter "token"))
         (delete-param (hunchentoot:post-parameter "delete"))
         (expires-param (hunchentoot:post-parameter "expires"))
         (entry (lookup-entry id)))
    (cond
      ((null entry)
       (setf (hunchentoot:return-code*) 404)
       (format nil "Not found~%"))
      ((or (null token) (not (string= token (entry-token entry))))
       (setf (hunchentoot:return-code*) 403)
       (format nil "Invalid token~%"))
      ;; Delete
      (delete-param
       (delete-entry id)
       (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
       (format nil "Deleted~%"))
      ;; Update expiry
      ((and expires-param (plusp (length expires-param)))
       (let* ((expires (parse-integer expires-param :junk-allowed t))
              (new-expiry (when expires
                            (compute-expiry-time (entry-size entry) :expires expires))))
         (if new-expiry
             (progn
               (update-entry-expiry id new-expiry)
               (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
               (format nil "Expiry updated~%"))
             (progn
               (setf (hunchentoot:return-code*) 400)
               (format nil "Invalid expiry value~%")))))
      (t
       (setf (hunchentoot:return-code*) 400)
       (format nil "No action specified (use 'delete' or 'expires')~%")))))

(defun handle-download (id)
  "Handle GET to /<id> - serve the file."
  (let ((entry (lookup-entry id)))
    (cond
      ((null entry)
       (setf (hunchentoot:return-code*) 404)
       (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
       (format nil "Not found~%"))
      ;; Check if expired
      ((and (entry-expires-at entry)
            (<= (entry-expires-at entry) (get-universal-time)))
       (delete-entry id)
       (setf (hunchentoot:return-code*) 404)
       (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
       (format nil "Expired~%"))
      (t
       (let ((path (file-data-path id)))
         (setf (hunchentoot:header-out :content-disposition) "inline")
         (hunchentoot:handle-static-file path (entry-content-type entry)))))))

;;; ============================================================
;;; Dispatcher
;;; ============================================================

(defclass crafterbin-acceptor (hunchentoot:easy-acceptor) ()
  (:documentation "Custom acceptor for CrafterBin."))

(defmethod hunchentoot:acceptor-dispatch-request ((acceptor crafterbin-acceptor)
                                                   request)
  (let* ((uri (hunchentoot:request-uri request))
         (method (hunchentoot:request-method request))
         ;; Strip leading slash, and any trailing custom filename
         ;; (e.g. /abcd/image.png -> abcd)
         (path (string-left-trim "/" uri))
         (id (let ((slash (position #\/ path)))
               (if slash (subseq path 0 slash) path))))
    (cond
      ;; Root
      ((or (string= path "") (string= path "/"))
       (case method
         (:get
          (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
          (landing-page))
         (:post
          (handle-upload))
         (t
          (setf (hunchentoot:return-code*) 405)
          "Method not allowed")))

      ;; File endpoint
      ((plusp (length id))
       (case method
         (:get (handle-download id))
         (:post (handle-manage id))
         (t
          (setf (hunchentoot:return-code*) 405)
          "Method not allowed")))

      (t
       (setf (hunchentoot:return-code*) 404)
       "Not found"))))

;;; ============================================================
;;; Server lifecycle
;;; ============================================================

(defun start-server ()
  "Start the HTTP server."
  (setf *acceptor*
        (make-instance 'crafterbin-acceptor
                       :address (config-host *config*)
                       :port (config-port *config*)
                       :access-log-destination nil
                       :message-log-destination *error-output*))
  (hunchentoot:start *acceptor*)
  (format *error-output* "~&[server] Listening on ~A:~D~%"
          (config-host *config*) (config-port *config*)))

(defun stop-server ()
  "Stop the HTTP server."
  (when *acceptor*
    (hunchentoot:stop *acceptor*)
    (setf *acceptor* nil))
  (format *error-output* "~&[server] Stopped~%"))
