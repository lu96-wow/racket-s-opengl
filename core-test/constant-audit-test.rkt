#lang racket/base

;; ============================================================
;; constant-audit-test.rkt —— 常量映射审计
;;
;; 运行：racket core-test/constant-audit-test.rkt
;;
;; 检查两件事：
;;   1. Racket 侧：rename.rkt 里的每个 (define gl-xxx GL_XXX)
;;      - RHS 必须是 opengl 包真实导出的常量
;;      - LHS 必须符合「GL_XXX → gl-xxx」的机械命名
;;        （与函数撞名时按设计用 var- 前缀；COPY_* 借用 _BINDING 别名）
;;      - 值必须和 C 常量一致
;;      - 教程表格涉及的缓冲目标 / usage hint 必须已收录
;;   2. GLSL 侧：racket-glsl 的内建变量 / 函数 / 类型 / 关键字表
;;      - canonical 名都是合法 GLSL 标识符
;;      - 每个别名都能反查回 canonical 名
;;
;; 注意：opengl 包导出 4000+ 个 GL_*（大量扩展/旧版），本包按设计
;; 只收录教程用到的核心常量。这里打印未收录数量，但不因「未收录」失败。
;; ============================================================

(require rackunit
         racket/file
         racket/list
         racket/set
         racket/string
         racket/runtime-path
         "../core/opengl/rename.rkt"
         glsl/core/glsl/names
         glsl/core/vocab/type-names)

(define-runtime-path here ".")
(define rename-path (build-path here ".." "core" "opengl" "rename.rkt"))
(define rename-src (file->string rename-path))
(define constants-path (build-path here ".." "core" "opengl" "constants.rkt"))
(define constants-src (file->string constants-path))
(define src (string-append rename-src "\n" constants-src))
(define rename-module-path `(file ,(path->string rename-path)))

;; ---------- 1) Racket 侧：rename.rkt ↔ opengl ----------

;; opengl 包导出的 GL_* 常量。
;; module->exports 返回两个值；第一个值的 car 是
;;   (0 (GL_XXX ()) (GL_YYY ()) ...)
(define-values (exported-values exported-syntaxes) (module->exports 'opengl))
(define gl-exports
  (for/list ([entry (in-list (cdr (car exported-values)))]
             #:when (regexp-match? #rx"^GL_[A-Z0-9_]+$" (symbol->string (car entry))))
    (car entry)))
(define gl-export-set (list->seteq gl-exports))

;; rename.rkt 里的 (define <racket-name> <GL_CONST>) 映射
(define mappings
  (for/list ([m (in-list (regexp-match*
                          #px"\\(define\\s+((?:gl|var)-[a-z0-9-]+)\\s+(GL_[A-Z0-9_]+)\\)"
                          src
                          #:match-select cdr))])
    (list (list-ref m 0) (list-ref m 1))))

;; rename.rkt 里的函数名，用来判断常量是否要加 var- 前缀
(define function-names
  (for/list ([m (in-list (regexp-match*
                          #px"\\(define\\s+(gl-[a-z0-9-]+)\\s+gl[A-Z]"
                          rename-src
                          #:match-select cdr))])
    (list-ref m 0)))
(define opengl-kebab-names
  (for/list ([n (in-list (map car (cdr (car exported-syntaxes))))]
             #:when (regexp-match? #rx"^gl-[a-z0-9-]+$" (symbol->string n)))
    (symbol->string n)))
(define function-set
  (list->set (append function-names opengl-kebab-names)))

(define (gl->kebab c-name)
  (string-append "gl-"
                 (string-replace (string-downcase (substring c-name 3)) "_" "-")))

;; opengl 包只导出了 GL_COPY_*_BUFFER_BINDING，教程映射借用了它们；
;; 名字仍保留 gl-copy-*-buffer，不按 RHS 机械换算。
(define copy-special
  (set "gl-copy-read-buffer" "gl-copy-write-buffer"))

(define (expected-racket-name c-name)
  (define k (gl->kebab c-name))
  (if (set-member? function-set k)
      (string-append "var-" (substring k 3))
      k))

(for ([m (in-list mappings)])
  (define r-name (car m))
  (define c-name (cadr m))
  (check-true (set-member? gl-export-set (string->symbol c-name))
              (format "~a: ~a 不是 opengl 导出的常量" r-name c-name))
  (unless (set-member? copy-special r-name)
    (check-equal? r-name (expected-racket-name c-name)
                  (format "~a: 命名不符合机械规则（~a → ~a）"
                          r-name c-name (expected-racket-name c-name))))
  (check-equal? (dynamic-require rename-module-path (string->symbol r-name))
                (dynamic-require 'opengl (string->symbol c-name))
                (format "~a 与 ~a 的值不一致" r-name c-name)))

;; 报告未收录数量（不失败：扩展/旧版常量不要求全部映射）
(define mapped-c
  (list->seteq (map (lambda (m) (string->symbol (cadr m))) mappings)))
(define missing (set-subtract gl-export-set mapped-c))
(printf "opengl GL_* exports: ~a\n" (set-count gl-export-set))
(printf "mapped by rename.rkt: ~a\n" (set-count mapped-c))
(printf "unmapped: ~a\n" (set-count missing))

;; 教程 02 · 2.2 表格涉及的常量必须已收录
(define required-constants
  '(GL_ARRAY_BUFFER GL_ELEMENT_ARRAY_BUFFER
    GL_UNIFORM_BUFFER GL_SHADER_STORAGE_BUFFER
    GL_ATOMIC_COUNTER_BUFFER GL_TRANSFORM_FEEDBACK_BUFFER
    GL_PIXEL_PACK_BUFFER GL_PIXEL_UNPACK_BUFFER
    GL_DRAW_INDIRECT_BUFFER GL_DISPATCH_INDIRECT_BUFFER
    GL_COPY_READ_BUFFER_BINDING GL_COPY_WRITE_BUFFER_BINDING
    GL_STATIC_DRAW GL_DYNAMIC_DRAW GL_STREAM_DRAW
    GL_STATIC_READ GL_DYNAMIC_READ GL_STREAM_READ
    GL_STATIC_COPY GL_DYNAMIC_COPY GL_STREAM_COPY))
(for ([c (in-list required-constants)])
  (check-true (set-member? mapped-c c)
              (format "教程表格要用的常量未映射：~a" c)))

;; ---------- 2) GLSL 侧：内建表自洽 ----------

(define (valid-glsl-identifier? x)
  (and (glsl-identifier? x) #t))

;; 内建变量
(for ([n (in-list glsl-builtin-variable-names)])
  (check-true (valid-glsl-identifier? n)
              (format "内建变量不是合法标识符：~a" n)))
(for ([p (in-list glsl-builtin-variable-aliases)])
  (check-equal? (glsl-name (car p)) (symbol->string (cdr p))
                (format "变量别名映射错误：~a" (car p))))

;; 内建函数
(for ([n (in-list glsl-builtin-function-names)])
  (check-true (valid-glsl-identifier? n)
              (format "内建函数不是合法标识符：~a" n)))
(for ([p (in-list glsl-builtin-function-aliases)])
  (check-equal? (glsl-function-name (car p)) (symbol->string (cdr p))
                (format "函数别名映射错误：~a" (car p))))

;; 内建类型 + 类型别名
(for ([n (in-list builtin-glsl-type-names)])
  (check-true (valid-glsl-identifier? n)
              (format "内建类型不是合法标识符：~a" n)))
(for ([p (in-list glsl-type-alias-forms)])
  (check-equal? (glsl-type-canonical-name (car p)) (symbol->string (cdr p))
                (format "类型别名映射错误：~a" (car p))))

;; 限定符 / layout key 别名
(for ([p (in-list glsl-qualifier-aliases)])
  (check-equal? (glsl-qualifier-name (car p)) (cdr p)
                (format "限定符别名映射错误：~a" (car p))))
(for ([p (in-list glsl-layout-key-aliases)])
  (check-equal? (glsl-layout-key-name (car p)) (symbol->string (cdr p))
                (format "layout key 别名映射错误：~a" (car p))))

(displayln "constant-audit 全部检查通过")
