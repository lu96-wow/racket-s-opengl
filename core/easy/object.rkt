#lang racket/base

;; ============================================================
;; gl · object.rkt —— GL 对象句柄：分配 / 删除 便捷层（Part 3.5）
;;
;; 「逻辑：glGen* / glDelete* 的单句柄与多句柄便利封装」。
;;   单句柄：返回 / 接收一个 GLuint
;;   多句柄：返回 / 接收一个 u32vector（或 id 列表）
;;
;;   gl-gen-buffers  (n) → u32vector        buffer-new             → GLuint
;;                                          buffers-new n          → u32vector
;;                                          buffers-new/values n   → n 个值
;;   gl-gen-vertex-arrays (n) → u32vector   vertex-array-new       → GLuint
;;                                          vertex-arrays-new n    → u32vector
;;                                          vertex-arrays-new/values n → n 个值
;;   gl-gen-textures (n) → u32vector        texture-new            → GLuint
;;                                          textures-new n         → u32vector
;;                                          textures-new/values n  → n 个值
;;   gl-gen-framebuffers (n) → u32vector    framebuffer-new        → GLuint
;;                                          framebuffers-new n     → u32vector
;;                                          framebuffers-new/values n → n 个值
;;   gl-gen-renderbuffers (n) → u32vector   renderbuffer-new       → GLuint
;;                                          renderbuffers-new n    → u32vector
;;                                          renderbuffers-new/values n → n 个值
;;   gl-delete-buffers (n, u32vector)       buffer-delete id
;;                                          buffers-delete ids
;;   （vertex-array / texture / framebuffer / renderbuffer 的 delete 同理）
;;
;; ★ 为什么返回裸 GLuint，而不是带 finalizer 的对象：
;;   GL 删除必须在「拥有该对象的上下文所在线程」执行；Racket 的终结器在 GC 线程 /
;;   不确定时机运行，直接 gl-delete-* 会 GL_INVALID_OPERATION 甚至崩溃；且 program↔shader
;;   之类依赖关系的释放顺序不保证。故本层**不挂终结器、不做自动回收**，生命周期由调用方
;;   手动管理（详见 DESIGN.md §3.1）。
;;
;; 命名：不用 gl-*（gl-* 只给 OpenGL C 符号的 1:1 机械映射，而 glGenBuffer 这个符号并不存在），
;;       走工具层 <资源>-<动词>：buffer-new / buffer-delete（单句柄），
;;       buffers-new / buffers-delete（多句柄，返回/接收 u32vector）。
;; 所有权：*-new 返回的句柄归调用方，用完自行 *-delete。
;; ============================================================

(require ffi/vector
         "../opengl/rename.rkt")

(provide buffer-new buffers-new buffers-new/values buffer-delete buffers-delete
         vertex-array-new vertex-arrays-new vertex-arrays-new/values vertex-array-delete vertex-arrays-delete
         texture-new textures-new textures-new/values texture-delete textures-delete
         framebuffer-new framebuffers-new framebuffers-new/values framebuffer-delete framebuffers-delete
         renderbuffer-new renderbuffers-new renderbuffers-new/values renderbuffer-delete renderbuffers-delete)

;; ---------- 分配：glGen*(1) → 单个 GLuint ----------
;; 内部那个 1 元 u32vector 是瞬时分配，取完即丢，可忽略。

(define (check-count who n)
  (unless (and (exact? n) (integer? n) (>= n 0))
    (error who "n 应为非负整数，实际 ~s" n))
  n)

(define (buffer-new)       (u32vector-ref (gl-gen-buffers 1) 0))
(define (vertex-array-new) (u32vector-ref (gl-gen-vertex-arrays 1) 0))
(define (texture-new)      (u32vector-ref (gl-gen-textures 1) 0))
(define (framebuffer-new)  (u32vector-ref (gl-gen-framebuffers 1) 0))
(define (renderbuffer-new) (u32vector-ref (gl-gen-renderbuffers 1) 0))

;; ---------- 多句柄分配：glGen*(n) → u32vector ----------
;; 多句柄场景直接用 raw 返回的 u32vector，避免“单句柄/多句柄”返回类型摇摆。
;; 生命周期仍然是调用方手动管理。

(define (alloc-ids who n alloc)
  (alloc (check-count who n)))

(define (buffers-new n)        (alloc-ids 'buffers-new n gl-gen-buffers))
(define (vertex-arrays-new n)  (alloc-ids 'vertex-arrays-new n gl-gen-vertex-arrays))
(define (textures-new n)       (alloc-ids 'textures-new n gl-gen-textures))
(define (framebuffers-new n)   (alloc-ids 'framebuffers-new n gl-gen-framebuffers))
(define (renderbuffers-new n)  (alloc-ids 'renderbuffers-new n gl-gen-renderbuffers))

;; ---------- 多句柄分配（多值版）：返回 n 个值 ----------
;; 适合固定数量的 define-values：
;;   (define-values (vbo ebo) (buffers-new/values 2))
;; 动态数量请用向量版 buffers-new + u32vector-ref，或 call-with-values。

(define (ids->values ids)
  (apply values (u32vector->list ids)))

(define (buffers-new/values n)       (ids->values (buffers-new n)))
(define (vertex-arrays-new/values n) (ids->values (vertex-arrays-new n)))
(define (textures-new/values n)      (ids->values (textures-new n)))
(define (framebuffers-new/values n)  (ids->values (framebuffers-new n)))
(define (renderbuffers-new/values n) (ids->values (renderbuffers-new n)))

;; ---------- 删除：GLuint → glDelete*(1, u32vector) ----------

(define (buffer-delete id)       (gl-delete-buffers 1 (u32vector id)))
(define (vertex-array-delete id) (gl-delete-vertex-arrays 1 (u32vector id)))
(define (texture-delete id)      (gl-delete-textures 1 (u32vector id)))
(define (framebuffer-delete id)  (gl-delete-framebuffers 1 (u32vector id)))
(define (renderbuffer-delete id) (gl-delete-renderbuffers 1 (u32vector id)))

;; ---------- 多句柄删除：u32vector / id 列表 → glDelete*(n, u32vector) ----------
(define (coerce-ids who ids)
  (cond
    [(u32vector? ids) ids]
    [(list? ids) (list->u32vector ids)]
    [else (error who "需要 u32vector 或 id 列表，实际 ~s" ids)]))

(define (free-ids who ids delete)
  (define v (coerce-ids who ids))
  (unless (zero? (u32vector-length v))
    (delete (u32vector-length v) v)))

(define (buffers-delete ids)       (free-ids 'buffers-delete ids gl-delete-buffers))
(define (vertex-arrays-delete ids) (free-ids 'vertex-arrays-delete ids gl-delete-vertex-arrays))
(define (textures-delete ids)      (free-ids 'textures-delete ids gl-delete-textures))
(define (framebuffers-delete ids)  (free-ids 'framebuffers-delete ids gl-delete-framebuffers))
(define (renderbuffers-delete ids) (free-ids 'renderbuffers-delete ids gl-delete-renderbuffers))
