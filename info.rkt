#lang info
;; ============================================================
;; racket-shader-opengl —— GLSL + OpenGL 包（collection: glsl-opengl）
;;
;; #lang glsl-opengl = (require glsl) + OpenGL 绑定 + 编译/链接胶水。
;; 依赖 racket-shader（集合 shader / glsl / slang）：
;;   - glsl 方言 + core（值层、模型、反射、产物、报错）
;;   - 本包叠加：core/opengl/rename.rkt（gl-*）、core/tool/{compile,program}.rkt
;;
;; 安装：先装 racket-shader，再装本包（或一次性 raco pkg install 两个目录）。
;; ============================================================

(define collection "glsl-opengl")

(define deps '("base" "racket-shader" "opengl"))
(define build-deps '("gui-lib" "rackunit-lib"))   ; core-test 用（需要 GL 上下文）

(define compile-omit-paths '("core-test"))

(define pkg-desc "GLSL + OpenGL for Racket: #lang glsl-opengl (OpenGL bindings + compile/link glue)")
(define pkg-authors '("lu96"))
(define license '("MIT"))
