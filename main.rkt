#lang racket/base

;; ============================================================
;; glsl-opengl/main.rkt —— #lang glsl-opengl 的模块语言（GLSL + OpenGL）
;;
;; 在 racket-shader 的 glsl 方言之上叠加 OpenGL 层：
;;
;;   (require glsl)                        GLSL 方言 + core（值层/模型/反射/产物/报错）
;;   core/opengl/rename.rkt                Part 3：OpenGL → Racket 命名（gl-*）
;;   core/easy/object.rkt                    GL 对象句柄：buffer-new / *-delete …
;;   core/easy/buffer.rkt                    GL 缓冲上传：buffer-upload / buffer-update
;;   core/easy/uniform.rkt                   uniform 上传：uniform-set!（按类型符号分派）
;;   core/meta/vertex-layout.rkt             表驱动代码生成：glsl-vertex-layout!
;;   core/meta/uniform-setter.rkt            uniform setter 生成：glsl-uniform-setter!
;;   core/tool/compile.rkt                 shader-compile（文本 → shader + 报错）
;;   core/tool/program.rkt                 链接 / program 生命周期
;;
;; 因为 (provide (all-from-out glsl))，#lang glsl-opengl 的 body 里
;; 既能用 GLSL 层的名字，也能用 gl-* / shader-compile / program-link。
;; 只要 OpenGL 时用 #lang glsl 即可（不拉 opengl）。
;; ============================================================

(require glsl
         "core/opengl/rename.rkt"
         "core/opengl/alias.rkt"
         "core/easy/object.rkt"
         "core/easy/buffer.rkt"
         "core/easy/uniform.rkt"
         "core/meta/vertex-layout.rkt"
         "core/meta/uniform-setter.rkt"
         "core/tool/compile.rkt"
         "core/tool/program.rkt")

(provide (all-from-out glsl)
         (all-from-out "core/opengl/rename.rkt")
         (all-from-out "core/opengl/alias.rkt")
         (all-from-out "core/easy/object.rkt")
         (all-from-out "core/easy/buffer.rkt")
         (all-from-out "core/easy/uniform.rkt")
         (all-from-out "core/meta/vertex-layout.rkt")
         (all-from-out "core/meta/uniform-setter.rkt")
         (all-from-out "core/tool/compile.rkt")
         (all-from-out "core/tool/program.rkt"))
