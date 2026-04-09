(in-package #:crafterbin/storage)

;;; ============================================================
;;; File entry metadata
;;; ============================================================

(defclass file-entry ()
  ((id :initarg :id :accessor entry-id)
   (filename :initarg :filename :accessor entry-filename
             :documentation "Original filename from upload")
   (content-type :initarg :content-type :accessor entry-content-type
                 :initform "application/octet-stream")
   (size :initarg :size :accessor entry-size :initform 0)
   (token :initarg :token :accessor entry-token
          :documentation "Management token returned via X-Token header")
   (ip :initarg :ip :accessor entry-ip :initform "")
   (user-agent :initarg :user-agent :accessor entry-user-agent :initform "")
   (created-at :initarg :created-at :accessor entry-created-at)
   (expires-at :initarg :expires-at :accessor entry-expires-at)
   (secret-p :initarg :secret-p :accessor entry-secret-p :initform nil))
  (:documentation "Metadata for a stored file."))

;;; ============================================================
;;; ID and token generation
;;; ============================================================

(defvar *id-chars* "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  "Character set for short IDs.")

(defun generate-id (&optional (length 4))
  "Generate a random short ID string."
  (let ((chars *id-chars*)
        (result (make-string length)))
    (dotimes (i length result)
      (setf (char result i) (char chars (random (length chars)))))))

(defun generate-secret-id ()
  "Generate a longer, hard-to-guess ID."
  (generate-id 24))

(defun generate-token ()
  "Generate a management token (hex string)."
  (ironclad:byte-array-to-hex-string
   (ironclad:random-data 16)))

;;; ============================================================
;;; Storage paths
;;; ============================================================

(defun data-dir ()
  "Return the data files directory."
  (merge-pathnames "files/" (uiop:ensure-directory-pathname (config-storage-dir *config*))))

(defun meta-dir ()
  "Return the metadata directory."
  (merge-pathnames "meta/" (uiop:ensure-directory-pathname (config-storage-dir *config*))))

(defun file-data-path (id)
  "Return the filesystem path for a stored file's data."
  (merge-pathnames id (data-dir)))

(defun file-meta-path (id)
  "Return the filesystem path for a stored file's metadata."
  (merge-pathnames (concatenate 'string id ".meta") (meta-dir)))

;;; ============================================================
;;; Metadata serialization
;;; ============================================================

(defgeneric serialize-meta (entry)
  (:documentation "Serialize file entry metadata to persistent storage."))

(defmethod serialize-meta ((entry file-entry))
  "Write file entry metadata to disk as a plist."
  (let ((path (file-meta-path (entry-id entry))))
    (ensure-directories-exist path)
    (with-open-file (out path :direction :output
                              :if-exists :supersede
                              :external-format :utf-8)
      (let ((*print-readably* t)
            (*print-pretty* nil))
        (print (list :id (entry-id entry)
                     :filename (entry-filename entry)
                     :content-type (entry-content-type entry)
                     :size (entry-size entry)
                     :token (entry-token entry)
                     :ip (entry-ip entry)
                     :user-agent (entry-user-agent entry)
                     :created-at (entry-created-at entry)
                     :expires-at (entry-expires-at entry)
                     :secret-p (entry-secret-p entry))
               out)))))

(defgeneric deserialize-meta (id)
  (:documentation "Deserialize file entry metadata from persistent storage."))

(defmethod deserialize-meta ((id string))
  "Read file entry metadata from disk. Returns a file-entry or NIL."
  (let ((path (file-meta-path id)))
    (when (probe-file path)
      (handler-case
          (with-open-file (in path :direction :input :external-format :utf-8)
            (let ((plist (read in)))
              (make-instance 'file-entry
                             :id (getf plist :id)
                             :filename (getf plist :filename)
                             :content-type (getf plist :content-type)
                             :size (getf plist :size)
                             :token (getf plist :token)
                             :ip (getf plist :ip)
                             :user-agent (getf plist :user-agent)
                             :created-at (getf plist :created-at)
                             :expires-at (getf plist :expires-at)
                             :secret-p (getf plist :secret-p))))
        (error () nil)))))

;;; ============================================================
;;; Content-type detection via magic bytes
;;; ============================================================

(defun detect-content-type-from-file (path)
  "Read the first few bytes of PATH and return a MIME type string if
   the magic bytes match a known format, or NIL otherwise."
  (handler-case
      (with-open-file (in path :element-type '(unsigned-byte 8))
        (let ((header (make-array 12 :element-type '(unsigned-byte 8) :initial-element 0)))
          (read-sequence header in)
          (cond
            ;; PNG: 89 50 4E 47 0D 0A 1A 0A
            ((and (>= (length header) 8)
                  (= (aref header 0) #x89)
                  (= (aref header 1) #x50)   ; P
                  (= (aref header 2) #x4E)   ; N
                  (= (aref header 3) #x47))  ; G
             "image/png")
            ;; JPEG: FF D8 FF
            ((and (>= (length header) 3)
                  (= (aref header 0) #xFF)
                  (= (aref header 1) #xD8)
                  (= (aref header 2) #xFF))
             "image/jpeg")
            ;; GIF: 47 49 46 38
            ((and (>= (length header) 4)
                  (= (aref header 0) #x47)   ; G
                  (= (aref header 1) #x49)   ; I
                  (= (aref header 2) #x46)   ; F
                  (= (aref header 3) #x38))  ; 8
             "image/gif")
            ;; WebP: RIFF....WEBP
            ((and (>= (length header) 12)
                  (= (aref header 0) #x52)   ; R
                  (= (aref header 1) #x49)   ; I
                  (= (aref header 2) #x46)   ; F
                  (= (aref header 3) #x46)   ; F
                  (= (aref header 8) #x57)   ; W
                  (= (aref header 9) #x45)   ; E
                  (= (aref header 10) #x42)  ; B
                  (= (aref header 11) #x50)) ; P
             "image/webp")
            ;; BMP: 42 4D
            ((and (>= (length header) 2)
                  (= (aref header 0) #x42)
                  (= (aref header 1) #x4D))
             "image/bmp")
            ;; PDF: 25 50 44 46
            ((and (>= (length header) 4)
                  (= (aref header 0) #x25)   ; %
                  (= (aref header 1) #x50)   ; P
                  (= (aref header 2) #x44)   ; D
                  (= (aref header 3) #x46))  ; F
             "application/pdf")
            ;; ZIP (and derivatives): 50 4B 03 04
            ((and (>= (length header) 4)
                  (= (aref header 0) #x50)   ; P
                  (= (aref header 1) #x4B)   ; K
                  (= (aref header 2) #x03)
                  (= (aref header 3) #x04))
             "application/zip")
            ;; GZIP: 1F 8B
            ((and (>= (length header) 2)
                  (= (aref header 0) #x1F)
                  (= (aref header 1) #x8B))
             "application/gzip")
            ;; MP3: FF FB, FF F3, FF F2 or ID3
            ((or (and (>= (length header) 2)
                      (= (aref header 0) #xFF)
                      (member (aref header 1) '(#xFB #xF3 #xF2)))
                 (and (>= (length header) 3)
                      (= (aref header 0) #x49)   ; I
                      (= (aref header 1) #x44)   ; D
                      (= (aref header 2) #x33)))  ; 3
             "audio/mpeg")
            ;; OGG: 4F 67 67 53
            ((and (>= (length header) 4)
                  (= (aref header 0) #x4F)   ; O
                  (= (aref header 1) #x67)   ; g
                  (= (aref header 2) #x67)   ; g
                  (= (aref header 3) #x53))  ; S
             "audio/ogg")
            ;; FLAC: 66 4C 61 43
            ((and (>= (length header) 4)
                  (= (aref header 0) #x66)   ; f
                  (= (aref header 1) #x4C)   ; L
                  (= (aref header 2) #x61)   ; a
                  (= (aref header 3) #x43))  ; C
             "audio/flac")
            ;; WAV: RIFF....WAVE
            ((and (>= (length header) 12)
                  (= (aref header 0) #x52)   ; R
                  (= (aref header 1) #x49)   ; I
                  (= (aref header 2) #x46)   ; F
                  (= (aref header 3) #x46)   ; F
                  (= (aref header 8) #x57)   ; W
                  (= (aref header 9) #x41)   ; A
                  (= (aref header 10) #x56)  ; V
                  (= (aref header 11) #x45)) ; E
             "audio/wav")
            ;; No match
            (t nil))))
    (error () nil)))

(defun refine-content-type (declared-type file-path)
  "If DECLARED-TYPE is generic (text/plain, application/octet-stream),
   try to detect the real type from the file's magic bytes."
  (if (member declared-type '("text/plain" "application/octet-stream")
              :test #'string-equal)
      (or (detect-content-type-from-file file-path)
          declared-type)
      declared-type))

;;; ============================================================
;;; Storage operations
;;; ============================================================

(defun init-storage ()
  "Ensure storage directories exist."
  (ensure-directories-exist (data-dir))
  (ensure-directories-exist (meta-dir)))

(defun id-exists-p (id)
  "Check if an ID is already in use."
  (or (probe-file (file-data-path id))
      (probe-file (file-meta-path id))))

(defun allocate-id (&optional secret-p)
  "Allocate a unique file ID."
  (loop for id = (if secret-p (generate-secret-id) (generate-id))
        unless (id-exists-p id)
          return id))

(defgeneric store-upload (source filename content-type size expires-at
                          &key ip user-agent secret-p)
  (:documentation "Store data from SOURCE. Returns the new file-entry."))

(defmethod store-upload ((source stream) filename content-type size expires-at
                         &key ip user-agent secret-p)
  "Store an uploaded file from an octet stream. Returns the new file-entry."
  (let* ((id (allocate-id secret-p))
         (token (generate-token))
         (data-path (file-data-path id))
         (entry (make-instance 'file-entry
                               :id id
                               :filename (or filename "unnamed")
                               :content-type (or content-type "application/octet-stream")
                               :size size
                               :token token
                               :ip (or ip "")
                               :user-agent (or user-agent "")
                               :created-at (get-universal-time)
                               :expires-at expires-at
                               :secret-p secret-p)))
    (ensure-directories-exist data-path)
    ;; Write the file data
    (with-open-file (out data-path :direction :output
                                   :if-exists :supersede
                                   :element-type '(unsigned-byte 8))
      (let ((buf (make-array 8192 :element-type '(unsigned-byte 8))))
        (loop for n = (read-sequence buf source)
              while (> n 0)
              do (write-sequence buf out :end n))))
    ;; Update actual size from disk
    (let ((actual-size (with-open-file (f data-path :element-type '(unsigned-byte 8)) (file-length f))))
      (when actual-size
        (setf (entry-size entry) actual-size)))
    ;; Refine content-type from magic bytes if the declared type is generic
    (let ((refined (refine-content-type (entry-content-type entry) data-path)))
      (unless (string-equal refined (entry-content-type entry))
        (setf (entry-content-type entry) refined)))
    ;; Write metadata
    (serialize-meta entry)
    entry))

(defmethod store-upload ((source pathname) filename content-type size expires-at
                         &key ip user-agent secret-p)
  "Store an uploaded file from a pathname. Returns the new file-entry."
  (with-open-file (in source :element-type '(unsigned-byte 8))
    (store-upload in
                  (or filename (file-namestring source))
                  content-type size expires-at
                  :ip ip :user-agent user-agent :secret-p secret-p)))

(defgeneric store-from-url (url expires-at &key ip user-agent secret-p)
  (:documentation "Fetch a remote URL and store it."))

(defmethod store-from-url ((url string) expires-at &key ip user-agent secret-p)
  "Fetch a remote URL and store it. Returns the new file-entry."
  (multiple-value-bind (body status headers)
      (drakma:http-request url :want-stream t :redirect 10
                               :connection-timeout 15
                               :additional-headers '(("User-Agent" . "CrafterBin/1.0")))
    (declare (ignore status))
    (let* ((ct (or (cdr (assoc :content-type headers)) "application/octet-stream"))
           (cl (let ((v (cdr (assoc :content-length headers))))
                 (when v (parse-integer v :junk-allowed t))))
           ;; Extract filename from URL
           (url-path (puri:uri-path (puri:parse-uri url)))
           (filename (when url-path
                       (let ((slash (position #\/ url-path :from-end t)))
                         (if slash (subseq url-path (1+ slash)) url-path)))))
      (when (and cl (config-max-size *config*) (> cl (config-max-size *config*)))
        (close body)
        (error "Remote file exceeds maximum size"))
      (unwind-protect
           (store-upload body filename ct (or cl 0) expires-at
                         :ip ip :user-agent user-agent :secret-p secret-p)
        (close body)))))

(defgeneric lookup-entry (id)
  (:documentation "Look up a file entry by ID."))

(defmethod lookup-entry ((id string))
  "Look up a file entry by ID. Returns the entry or NIL."
  (let ((entry (deserialize-meta id)))
    (when (and entry (probe-file (file-data-path id)))
      entry)))

(defgeneric delete-entry (id)
  (:documentation "Delete a file and its metadata."))

(defmethod delete-entry ((id string))
  "Delete a file and its metadata."
  (let ((data-path (file-data-path id))
        (meta-path (file-meta-path id)))
    (when (probe-file data-path) (delete-file data-path))
    (when (probe-file meta-path) (delete-file meta-path))
    t))

(defgeneric update-entry-expiry (id new-expires-at)
  (:documentation "Update the expiry time for a file."))

(defmethod update-entry-expiry ((id string) new-expires-at)
  "Update the expiry time for a file."
  (let ((entry (deserialize-meta id)))
    (when entry
      (setf (entry-expires-at entry) new-expires-at)
      (serialize-meta entry)
      entry)))

(defun list-expired-entries ()
  "Return a list of IDs whose files have expired."
  (let ((now (get-universal-time))
        (expired nil))
    (dolist (meta-file (uiop:directory-files (meta-dir) "*.meta"))
      (handler-case
          (with-open-file (in meta-file :direction :input :external-format :utf-8)
            (let* ((plist (read in))
                   (exp (getf plist :expires-at))
                   (id (getf plist :id)))
              (when (and exp id (<= exp now))
                (push id expired))))
        (error () nil)))
    expired))
