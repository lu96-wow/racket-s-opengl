#lang glsl-opengl

;; ============================================================
;; lang-opengl-test.rkt —— #lang glsl-opengl 顶层入口端到端测试
;;
;; 运行：racket core-test/lang-opengl-test.rkt
;; 验证 #lang glsl-opengl == (require glsl) + OpenGL 层：
;;   - 纯 GLSL 层的名字透传（vec3 / vadd / shader-size / parse-error-log）
;;   - gl-* 与 shader-compile / program-link 等可用
;; ============================================================

(require rackunit racket/string)

;; ---------- glsl 层名字透传（来自 racket-glsl 包）----------
(check-true (f32vector? (vec3 1.0 2.0 3.0)))
(check-equal? (f32vector->list (vadd (vec2 1.0 2.0) (vec2 3.0 4.0))) '(4.0 6.0))
(check-equal? (shader-size 'vec3) 3)
(check-true (procedure? parse-error-log))

;; ---------- OpenGL 层名字（来自本包）----------
(check-true (procedure? gl-create-shader))
(check-true (procedure? shader-compile))
(check-true (procedure? program-link))
(check-true (procedure? program-use))
(check-true (procedure? shader-delete))
(check-true (procedure? program-delete))
;; 旧名（deprecated）仍是子程序
(check-true (procedure? compile-shader))
(check-true (procedure? link-program))
(check-true (procedure? use-program))

;; ---------- (glsl ...) 宏在 #lang glsl-opengl 下同样工作 ----------
(define vert
  (glsl (version 330 core)
        (layout (location 0) in vec3 aPos)
        (define (main) void
          (set! gl_Position (vec4 aPos 1.0)))))
(check-true (shader-program? vert))
(check-true (string-contains? (shader-program-src vert) "#version 330 core"))

(displayln "lang (glsl-opengl) 全部测试通过")
