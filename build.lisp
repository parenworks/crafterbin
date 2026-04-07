(require :asdf)
(load "~/quicklisp/setup.lisp")
(push (uiop:getcwd) asdf:*central-registry*)
(ql:quickload :crafterbin)
(sb-ext:save-lisp-and-die "crafterbin"
                          :toplevel #'crafterbin:main
                          :executable t
                          :compression t)
