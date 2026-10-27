;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; Guix package template for dnie-pkcs11-compat.
;; Build with:  guix build -f guix.scm
;;
;; This is a template: import module names and the OpenSC layout may change
;; between Guix revisions. Adjust if your checkout differs.

(use-modules (guix packages)
             (guix gexp)
             (guix git-download)
             (guix build-system gnu)
             (guix licenses)
             (gnu packages security-token)   ; opensc
             (gnu packages tls))             ; p11-kit

(package
  (name "dnie-pkcs11-compat")
  (version "0.2.2")
  (source
   (local-file "." "dni-e-checkout"
               #:recursive? #t
               #:select?
               (lambda (file stat)
                 (not (or (string-contains file "/.git")
                          (string-contains file "/reference")
                          (string-contains file "/artifacts")
                          (string-suffix? ".so" file)
                          (string=? file "passwd")
                          (string-suffix? ".pin" file)
                          (string-suffix? "firmado.pdf" file)
                          (string-suffix? ".sig0" file))))))
  (build-system gnu-build-system)
  (arguments
   (list
    #:tests? #f
    #:phases
    #~(modify-phases %standard-phases
        (delete 'configure)
        (replace 'build
          (lambda _
            (invoke "make" "-C" "src/pkcs11-shim"
                    "MULTIARCH="
                    (string-append "MODULE_PATH=" #$opensc
                                   "/lib/opensc-pkcs11.so"))))
        (replace 'install
          (lambda _
            (invoke "make" "-C" "src/pkcs11-shim" "install"
                    "MULTIARCH="
                    (string-append "PREFIX=" #$output)
                    (string-append "P11KIT_MODULEDIR=" #$output
                                   "/share/p11-kit/modules")
                    (string-append "DOCDIR=" #$output
                                   "/share/doc/dnie-pkcs11-compat")))))))
  (inputs (list opensc))
  (synopsis "PKCS#11 compatibility module for the Spanish DNIe")
  (description
   "OpenSC-based PKCS#11 module that exposes the libpkcs11-dnie.so name and
ABI expected by Spanish DNIe applications and guides, on any architecture
supported by OpenSC, including aarch64 and riscv64.")
  (home-page "https://github.com/ZiTAL/dni-e")
  (license gpl3+))
