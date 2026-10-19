#lang racket/base

;; ============================================================
;; access-api-test.rkt —— GL 对象/取用便捷层的「可执行约束」+ 名字可用性
;;
;; 运行：racket racket-shader-opengl/core-test/access-api-test.rkt   （无需显示器）
;;
;; 1) 新 API 名可用（buffer-new / buffer-upload / …）
;; 2) 不变量（DESIGN.md §3.1）：
;;      源码中不得出现「保留 Racket 侧 C 指针」或「用终结器自动删 GL 对象」的用法，
;;      禁止词表见 forbidden。只扫 core/（不含 core-test，避免检查文件自身的词表误报）。
;; ============================================================

(require rackunit
         racket/file
         racket/list
         racket/path
         racket/string
         racket/runtime-path
         glsl-opengl
         (only-in opengl
                  GL_UNIFORM_BUFFER
                  GL_SHADER_STORAGE_BUFFER
                  GL_PIXEL_UNPACK_BUFFER
                  GL_PIXEL_PACK_BUFFER
                  GL_DRAW_INDIRECT_BUFFER
                  GL_ATOMIC_COUNTER_BUFFER
                  GL_TRANSFORM_FEEDBACK_BUFFER
                  GL_DISPATCH_INDIRECT_BUFFER
                  GL_STATIC_DRAW GL_DYNAMIC_DRAW GL_STREAM_DRAW
                  GL_STATIC_READ GL_DYNAMIC_READ GL_STREAM_READ
                  GL_STATIC_COPY GL_DYNAMIC_COPY GL_STREAM_COPY
                  GL_COPY_READ_BUFFER_BINDING
                  GL_COPY_WRITE_BUFFER_BINDING))

;; ---------- 1) 名字可用 ----------
(check-true (procedure? buffer-new))
(check-true (procedure? buffers-new))
(check-true (procedure? buffers-new/values))
(check-true (procedure? buffer-delete))
(check-true (procedure? buffers-delete))
(check-true (procedure? vertex-arrays-new))
(check-true (procedure? vertex-arrays-new/values))
(check-true (procedure? vertex-arrays-delete))
(check-true (procedure? textures-new))
(check-true (procedure? textures-new/values))
(check-true (procedure? textures-delete))
(check-true (procedure? framebuffers-new))
(check-true (procedure? framebuffers-new/values))
(check-true (procedure? framebuffers-delete))
(check-true (procedure? renderbuffers-new))
(check-true (procedure? renderbuffers-new/values))
(check-true (procedure? renderbuffers-delete))

;; 多句柄 API 的纯校验路径（不碰 GL 上下文）
(check-exn exn:fail? (lambda () (buffers-new -1)))
(check-exn exn:fail? (lambda () (buffers-new 1.5)))
(check-exn exn:fail? (lambda () (buffers-new/values -1)))
(check-equal? (buffers-delete '()) (void))
(check-equal? (buffers-delete (u32vector)) (void))
(check-equal? (textures-delete '()) (void))
(check-equal? (vertex-arrays-delete '()) (void))
(check-equal? (framebuffers-delete '()) (void))
(check-equal? (renderbuffers-delete '()) (void))
(check-exn exn:fail? (lambda () (buffers-delete 'bad)))
(check-exn exn:fail? (lambda () (textures-new -1)))
(check-exn exn:fail? (lambda () (vertex-arrays-new 2.5)))
(check-true (procedure? vertex-array-new))
(check-true (procedure? vertex-array-delete))
(check-true (procedure? texture-new))
(check-true (procedure? texture-delete))
(check-true (procedure? framebuffer-new))
(check-true (procedure? framebuffer-delete))
(check-true (procedure? renderbuffer-new))
(check-true (procedure? renderbuffer-delete))
(check-true (procedure? buffer-upload))
(check-true (procedure? buffer-update))

;; 语义别名：名字不同，过程相同
(check-true (procedure? gl-set-clear-color))
(check-true (eq? gl-set-clear-color gl-clear-color))
(check-true (eq? gl-clear-buffers gl-clear))
(check-true (eq? gl-set-viewport gl-viewport))
(check-true (eq? gl-set-blend-function gl-blend-func))
(check-true (eq? gl-set-depth-write gl-depth-mask))
(check-true (eq? gl-set-pixel-store gl-pixel-store-i))
(check-true (eq? gl-set-texture-parameter gl-tex-parameter-i))
(check-true (eq? gl-set-vertex-attrib-pointer gl-vertex-attrib-pointer))

;; 缓冲目标常量：Racket 名必须与 C 常量同值（教程 02 · 2.2 的表）
(check-equal? gl-uniform-buffer GL_UNIFORM_BUFFER)
(check-equal? gl-shader-storage-buffer GL_SHADER_STORAGE_BUFFER)
(check-equal? gl-pixel-unpack-buffer GL_PIXEL_UNPACK_BUFFER)
(check-equal? gl-pixel-pack-buffer GL_PIXEL_PACK_BUFFER)
(check-equal? gl-draw-indirect-buffer GL_DRAW_INDIRECT_BUFFER)
(check-equal? gl-atomic-counter-buffer GL_ATOMIC_COUNTER_BUFFER)
(check-equal? gl-transform-feedback-buffer GL_TRANSFORM_FEEDBACK_BUFFER)
(check-equal? gl-dispatch-indirect-buffer GL_DISPATCH_INDIRECT_BUFFER)

;; usage hint：draw / read / copy 三组
(check-equal? gl-static-draw GL_STATIC_DRAW)
(check-equal? gl-dynamic-draw GL_DYNAMIC_DRAW)
(check-equal? gl-stream-draw GL_STREAM_DRAW)
(check-equal? gl-static-read GL_STATIC_READ)
(check-equal? gl-dynamic-read GL_DYNAMIC_READ)
(check-equal? gl-stream-read GL_STREAM_READ)
(check-equal? gl-static-copy GL_STATIC_COPY)
(check-equal? gl-dynamic-copy GL_DYNAMIC_COPY)
(check-equal? gl-stream-copy GL_STREAM_COPY)

;; opengl 包只导出了 GL_COPY_*_BUFFER_BINDING，数值与 target 常量相同
(check-equal? gl-copy-read-buffer GL_COPY_READ_BUFFER_BINDING)
(check-equal? gl-copy-write-buffer GL_COPY_WRITE_BUFFER_BINDING)

;; ---------- 2) 不变量检查 ----------
(define forbidden
  '("cpointer" "ptr-add" "ptr-ref" "ptr-set!"
    "register-finalizer" "will-register"
    "gl-map-buffer" "gl-map-buffer-range"))

(define (rkt-files dir)
  (if (directory-exists? dir)
      (for/list ([p (in-directory dir)]
                 #:when (regexp-match? #rx"[.]rkt$" (path->string p)))
        p)
      '()))

;; 本文件所在目录 = racket-shader-opengl/core-test
(define-runtime-path here ".")
(define pkg-root  (simplify-path (build-path here "..")))
(define glsl-root (simplify-path (build-path here ".." ".." "racket-shader")))
(define scan-roots (list (build-path pkg-root "core")
                         (build-path glsl-root "core")))

;; 1:1 映射文件本身不算「使用」：rename.rkt 收录 gl-map-buffer 等名字是
;; 为了给调用方一个 kebab 名，不变量约束的是 core 里的实现代码。
(define (mapping-file? f)
  (or (string-suffix? (path->string f) "opengl/rename.rkt")
      (string-suffix? (path->string f) "opengl/alias.rkt")))

(define offenders
  (for*/list ([dir (in-list scan-roots)]
              [f (in-list (rkt-files dir))]
              #:unless (mapping-file? f)
              [tok (in-list forbidden)]
              #:when (string-contains? (file->string f) tok))
    (list (path->string f) tok)))

(check-equal? offenders '()
              "源码不得出现保留 C 指针 / 终结器自动删 GL 对象的用法（见 racket-shader-opengl/DESIGN.md §3.1）")

;; ---------- 3) 便利层（core/easy）的依赖边界 ----------
;; core/easy 的边界按层分：
;;   基础文件（object/buffer/uniform/attrib）：只组合 raw gl + 值层，不碰 GLSL 文本、不碰胶水；
;;   read/：可以 require glsl/（读名字、读编译期接口表），但不碰胶水 core/tool。
(define easy-dir (build-path pkg-root "core" "easy"))
(define base-files
  (for/list ([n (in-list '("object.rkt" "buffer.rkt" "uniform.rkt" "attrib.rkt"))])
    (build-path easy-dir n)))
(define mode-dirs (list (build-path easy-dir "read")))

(define (dep-offenders files forbidden)
  (for*/list ([f (in-list files)]
              [tok (in-list forbidden)]
              #:when (string-contains? (file->string f) tok))
    (list (path->string f) tok)))

(check-equal? (dep-offenders base-files '("glsl/" "tool/")) '()
              "core/easy 基础文件不得 require glsl/（语言文本）或 tool/（胶水）")

(check-equal? (append* (for/list ([d (in-list mode-dirs)])
                         (dep-offenders (rkt-files d) '("tool/"))))
              '()
              "core/easy/read 不得 require tool/（胶水）")

(displayln "access-api 全部检查通过")
