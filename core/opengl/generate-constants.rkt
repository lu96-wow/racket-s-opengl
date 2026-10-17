#lang racket/base

;; ============================================================
;; generate-constants.rkt —— 从 opengl 包生成 constants.rkt
;;
;; 运行：racket core/opengl/generate-constants.rkt
;;
;; 规则：
;;   GL_XXX_YYY        → gl-xxx-yyy
;;   与 rename.rkt 的 gl- 函数撞名 → var-xxx-yyy（历史约定）
;;   opengl 未导出 GL_COPY_*_BUFFER → 借用 GL_COPY_*_BUFFER_BINDING
;;
;; 只生成常量；函数映射仍在 rename.rkt 手写。生成后请跑
;; core-test/constant-audit-test.rkt 验证。
;; ============================================================

(require racket/file
         racket/list
         racket/runtime-path
         racket/set
         racket/string
         opengl)

(define-runtime-path here ".")
(define rename-path (build-path here "rename.rkt"))
(define constants-path (build-path here "constants.rkt"))

;; opengl 导出的 GL_* 常量
(define-values (exported-values exported-syntaxes) (module->exports 'opengl))
(define exported-names
  (append (map car (cdr (car exported-values)))
          (map car (cdr (car exported-syntaxes)))))
(define gl-names
  (sort
   (for/list ([entry (in-list (cdr (car exported-values)))]
              #:when (regexp-match? #rx"^GL_[A-Z0-9_]+$" (symbol->string (car entry))))
     (symbol->string (car entry)))
   string<?))

;; rename.rkt 里已有的 gl- 函数名：常量撞名时转 var-
(define rename-src (file->string rename-path))
;; 撞名对象包括 rename.rkt 里的函数，以及 opengl 自己导出的 kebab 工具
;; （gl-version / gl-extensions 等）；撞名常量统一加 var- 前缀。
(define function-names
  (list->set
   (append
    (for/list ([m (in-list (regexp-match*
                            #px"\\(define\\s+(gl-[a-z0-9-]+)\\s+gl[A-Z]"
                            rename-src
                            #:match-select cdr))])
      (list-ref m 0))
    (for/list ([n (in-list exported-names)]
               #:when (regexp-match? #rx"^gl-[a-z0-9-]+$" (symbol->string n)))
      (symbol->string n)))))

(define (gl->racket-name c-name)
  (define k (string-append "gl-"
                           (string-replace (string-downcase (substring c-name 3))
                                           "_" "-")))
  (if (set-member? function-names k)
      (string-append "var-" (substring k 3))
      k))

(define rows
  (for/list ([c (in-list gl-names)])
    (list (gl->racket-name c) c)))

;; opengl 包没有直接导出这两个 target，只导出同值的 _BINDING 查询别名
(define special-rows
  (list (list "gl-copy-read-buffer"  "GL_COPY_READ_BUFFER_BINDING")
        (list "gl-copy-write-buffer" "GL_COPY_WRITE_BUFFER_BINDING")))

(define all-rows (append rows special-rows))
(define width (apply max (map (lambda (r) (string-length (car r))) all-rows)))

(with-output-to-file constants-path #:exists 'replace
  (lambda ()
    (displayln "#lang racket/base")
    (displayln "")
    (displayln ";; ============================================================")
    (displayln ";; constants.rkt —— GL_* → gl-* 常量全量映射（生成文件，勿手改）")
    (displayln ";;")
    (displayln ";; 生成：racket core/opengl/generate-constants.rkt")
    (displayln ";; 规则：GL_XXX_YYY → gl-xxx-yyy；与函数撞名时用 var- 前缀。")
    (displayln ";; opengl 包未直接导出 GL_COPY_*_BUFFER，借用 _BINDING 别名。")
    (displayln ";; ============================================================")
    (displayln "")
    (displayln "(require opengl)")
    (displayln "")
    (displayln "(provide (all-defined-out))")
    (displayln "")
    (for ([r (in-list all-rows)])
      (define name (car r))
      (define c-name (cadr r))
      (printf "(define ~a ~a ~a)\n"
              name
              (make-string (- width (string-length name)) #\space)
              c-name))))

(printf "wrote ~a constants to ~a\n" (length all-rows) constants-path)
