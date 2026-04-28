(defsystem #:crafterbin
  :description "CrafterBin - a temporary file sharing service"
  :version "1.0.0"
  :author "Glenn Etherington"
  :license "MIT"
  :depends-on (#:hunchentoot
               #:ironclad
               #:bordeaux-threads
               #:unix-opts
               #:drakma
               #:trivial-mimes
               #:babel
               #:alexandria
               #:local-time
               #:puri)
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "packages")
                             (:file "config")
                             (:file "storage")
                             (:file "retention")
                             (:file "scan")
                             (:file "rate-limit")
                             (:file "cleanup")
                             (:file "server")
                             (:file "main")))))
