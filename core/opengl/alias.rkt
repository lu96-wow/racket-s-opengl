#lang racket/base

;; ============================================================
;; Part 3 · opengl/alias.rkt —— 语义别名（不是 C API 的 1:1 映射）
;; ============================================================
;; rename.rkt 是**机械**映射：C 符号 → kebab-case，名字尽量保持原样。
;; 但有些 OpenGL 名字没有准确表达“它在做什么”，例如：
;;
;;   glClearColor  → 它只是**设置**清屏颜色，并不会清屏
;;   glClear       → 它才真正清缓冲
;;
;; 本文件放这类“语义别名”：只改名字，不改变任何行为，也不替代 raw 名。
;; 需要新的别名时，直接在这里加一行：
;;
;;   (define gl-新名字 gl-原名字)
;;
;; 注意：
;;   - 不要把这里变成“另一套 API”；raw 名永远保留。
;;   - 别名和原函数是同一个过程，eq? 为 #t。
;;   - 命名优先用动词开头：set- / clear- / bind- / draw- …
;; ============================================================

(require "rename.rkt")

(provide (all-defined-out))

;; ---------- 清屏 / 状态设置 ----------

;; glClearColor 只设置颜色，不执行清屏；真正的清屏是 glClear。
(define gl-set-clear-color gl-clear-color)

;; glClear 根据 mask 清一个或多个缓冲；名字里补上 buffers。
(define gl-clear-buffers gl-clear)

;; glViewport 设置 NDC → 窗口像素的映射区域。
(define gl-set-viewport gl-viewport)

;; glBlendFunc 设置混合函数，不是“执行混合”。
(define gl-set-blend-function gl-blend-func)

;; glDepthMask 控制深度缓冲是否可写（#t/#f），不是读掩码。
(define gl-set-depth-write gl-depth-mask)

;; ---------- 纹理 / 像素状态 ----------

;; glPixelStorei 设置像素打包/解包参数。
(define gl-set-pixel-store gl-pixel-store-i)

;; glTexParameteri 设置纹理采样参数（过滤、wrap 等）。
(define gl-set-texture-parameter gl-tex-parameter-i)

;; ---------- 顶点属性 ----------

;; glVertexAttribPointer 描述一个顶点属性如何从当前 buffer 读取。
(define gl-set-vertex-attrib-pointer gl-vertex-attrib-pointer)
