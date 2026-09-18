;;; wsm-lazarus — Guix development manifest (профіль FPC/Lazarus субстрата)
;;; Використання:
;;;   скороминучий:  guix shell -m manifest.scm
;;;   постійний:     guix package -p ~/.guix-profiles/wsm-lazarus -m manifest.scm
;;;   активувати:    export PATH="$HOME/.guix-profiles/wsm-lazarus/bin:$PATH"
;;;
;;; На відміну від wsm-graalvm/guix.scm (pinned бінарний GraalVM), тут
;;; toolchain — стандартний upstream fpc + lazarus з GNU Guix, тому окремий
;;; guix.scm не потрібен: сам пакет «fpc» і є субстратним компілятором.

(use-modules (guix packages)
             (gnu packages base)
             (gnu packages compression)
             (gnu packages pascal)
             (gnu packages version-control))

(packages->manifest
 (list fpc
       lazarus
       git
       coreutils
       gnu-make))