#lang racket/base

;; ============================================================
;; meta-test.rkt —— 表驱动代码生成：glsl-vertex-layout!
;; 运行：racket racket-shader-opengl/core-test/meta-test.rkt
;; 覆盖：从 shader 接口表 + struct 字段表在编译期生成 gl-vertex-attrib-pointer 字面量；
;;       数量/类型不匹配 → 编译期报错
;; ============================================================

(require rackunit
         racket/list
         glsl-opengl)

;; ---------- 编译期表：glsl-shader 绑 <name>-interface；shader-struct 绑 <name>-fields ----------
(shader-struct vertex (vec3 pos) (vec3 normal) (vec2 uv))
(glsl-shader vert
  (version 330 core)
  (layout (location 0) in vec3 pos)        ; 属性名 = struct 字段名（对称标识符）
  (layout (location 1) in vec3 normal)
  (layout (location 2) in vec2 uv)
  (define (main) void))

;; 直接检查两张表
(check-equal? (vertex-fields) '((pos vec3) (normal vec3) (uv vec2)))
(check-equal? (map shader-var-name (shader-interface-vars (datum->shader-interface (vert-interface))))
              '(pos normal uv))

;; ---------- 展开：字面量 gl-* 调用（按名字对齐） ----------
(define (sublists d)
  (cond [(pair? d) (cons d (append-map sublists d))]
        [else '()]))
(define ex (syntax->datum (expand #'(glsl-vertex-layout! vert vertex))))

(check-true (and (member '(#%app gl-vertex-attrib-pointer '0 '3 gl-float '#f '32 '0) (sublists ex)) #t))
(check-true (and (member '(#%app gl-enable-vertex-attrib-array '0) (sublists ex)) #t))
(check-true (and (member '(#%app gl-vertex-attrib-pointer '1 '3 gl-float '#f '32 '12) (sublists ex)) #t))
(check-true (and (member '(#%app gl-vertex-attrib-pointer '2 '2 gl-float '#f '32 '24) (sublists ex)) #t))
(check-true (and (member '(#%app gl-enable-vertex-attrib-array '2) (sublists ex)) #t))

;; ---------- 顺序无关：shader in 顺序与 struct 字段顺序不同也能按名字对上 ----------
;; shader：normal 在 location 0、pos 在 location 1；struct：pos 在前
(shader-struct swapped (vec3 pos) (vec3 normal))
(glsl-shader vswap
  (version 330 core)
  (layout (location 0) in vec3 normal)
  (layout (location 1) in vec3 pos)
  (define (main) void))
(define ex-swap (syntax->datum (expand #'(glsl-vertex-layout! vswap swapped))))
;; pos 在 offset 0 → 绑到 location 1；normal 在 offset 12 → 绑到 location 0
(check-true (and (member '(#%app gl-vertex-attrib-pointer '1 '3 gl-float '#f '24 '0) (sublists ex-swap)) #t))
(check-true (and (member '(#%app gl-vertex-attrib-pointer '0 '3 gl-float '#f '24 '12) (sublists ex-swap)) #t))

;; ---------- 编译期校验：类型 / 字段缺失 / in 多余 ----------
(shader-struct bad (vec3 pos) (vec2 normal) (vec2 uv))       ; 字段 normal 类型不符
(check-exn exn:fail? (lambda () (expand #'(glsl-vertex-layout! vert bad))))

(shader-struct few (vec3 pos))                                ; 字段少 → shader 的 normal/uv 无对应
(check-exn exn:fail? (lambda () (expand #'(glsl-vertex-layout! vert few))))

(shader-struct extra (vec3 pos) (vec3 normal) (vec2 uv) (vec3 tail))  ; 字段多 → 无对应 in
(check-exn exn:fail? (lambda () (expand #'(glsl-vertex-layout! vert extra))))

;; ---------- glsl-uniform-setter!：按名字 + 接口推类型 ----------
(glsl-shader ushader
  (version 330 core)
  (uniform mat4 uMVP)
  (uniform vec3 uLightPos)
  (uniform float uTime)
  (uniform sampler2D uTex))
(define uprog 0)
(glsl-uniform-setter! uprog ushader)

;; 每个 uniform 都生成了 setter（名字来自 uniform 名）
(check-true (procedure? set-uMVP!))
(check-true (procedure? set-uLightPos!))
(check-true (procedure? set-uTime!))
(check-true (procedure? set-uTex!))

;; 多 program 命名空间：#:prefix（避免同名 uniform 撞）
(glsl-uniform-setter! uprog ushader #:prefix "obj-")
(check-true (procedure? set-obj-uMVP!))
(check-true (procedure? set-obj-uLightPos!))

;; 多 stage：合并 vertex + fragment 的 uniform；同名去重、类型一致
(glsl-shader vsh (version 330 core) (uniform mat4 uMVP) (uniform mat3 uNormalMatrix))
(glsl-shader fsh (version 330 core) (uniform vec3 uColor) (uniform mat4 uMVP))
(define mprog 0)
(glsl-uniform-setter! mprog vsh fsh #:prefix "m-")
(check-true (procedure? set-m-uMVP!))
(check-true (procedure? set-m-uNormalMatrix!))
(check-true (procedure? set-m-uColor!))

;; 同名 uniform 类型冲突 → 编译期报错
(glsl-shader fsh-bad (version 330 core) (uniform vec3 uMVP))
(check-exn exn:fail? (lambda () (expand #'(glsl-uniform-setter! mprog vsh fsh-bad))))

;; 拼错名字 → 未绑定标识符 → 编译期错误（而 uniform-set! 的运行期静默 -1 不再发生）
(check-exn exn:fail? (lambda () (eval '(set-uMPV! 1.0))))

;; 类型从接口推断：展开 setter 定义，看 uniform-set! 收到的是正确的类型符号
(define setter-body
  (syntax->datum (expand #'(glsl-uniform-setter! uprog ushader))))
(check-true (and (member ''mat4 (sublists setter-body)) #t))
(check-true (and (member ''vec3 (sublists setter-body)) #t))
(check-true (and (member ''sampler2D (sublists setter-body)) #t))


;; ---------- 连字符标识符：interface / vertex-layout / uniform-setter ----------
;; 表面名保留连字符；GLSL 名归一成下划线（或内建变量的规范拼写）。
(shader-struct hyp-vertex (vec3 model-pos) (vec3 normal-vec))
(glsl-shader hyp-vert
  (version 330 core)
  (layout (location 0) in vec3 model-pos)
  (layout (location 1) in vec3 normal-vec)
  (uniform mat4 u-model-view)
  (uniform float u-time)
  (define (main) void))

(define hyp-ifc (shader-program-interface hyp-vert))
(check-equal? (map shader-var-name (shader-interface-vars hyp-ifc))
              '(model-pos normal-vec u-model-view u-time))
(check-equal? (map shader-var-source-name (shader-interface-vars hyp-ifc))
              '(model_pos normal_vec u_model_view u_time))
;; 表面名 / GLSL 名都能查
(check-eq? (shader-interface-ref hyp-ifc 'u-model-view)
           (shader-interface-ref hyp-ifc 'u_model_view))

;; vertex-layout 按归一后的 GLSL 名对齐（struct 字段 model-pos ↔ in model-pos）
(define hyp-ex (syntax->datum (expand #'(glsl-vertex-layout! hyp-vert hyp-vertex))))
(check-true (and (member '(#%app gl-vertex-attrib-pointer '0 '3 gl-float '#f '24 '0)
                         (sublists hyp-ex)) #t))
(check-true (and (member '(#%app gl-vertex-attrib-pointer '1 '3 gl-float '#f '24 '12)
                         (sublists hyp-ex)) #t))

;; uniform setter：Racket 名保持连字符，uniform-location 用 GLSL 名
(glsl-uniform-setter! uprog hyp-vert #:prefix "hyp-")
(check-true (procedure? set-hyp-u-model-view!))
(check-true (procedure? set-hyp-u-time!))
(define hyp-setter-body
  (syntax->datum (expand #'(glsl-uniform-setter! uprog hyp-vert #:prefix "hyp-"))))
(check-true (and (member ''"u_model_view" (sublists hyp-setter-body)) #t))
(check-true (and (member ''"u_time" (sublists hyp-setter-body)) #t))

;; 多 stage：u-x 与 u_x 生成同一个 GLSL uniform，按第一次出现的表面名生成 setter
(glsl-shader hyp-v (version 330 core) (uniform float u-x))
(glsl-shader hyp-f (version 330 core) (uniform float u_x))
(glsl-uniform-setter! uprog hyp-v hyp-f #:prefix "mix-")
(check-true (procedure? set-mix-u-x!))
(define mix-setter-body
  (syntax->datum (expand #'(glsl-uniform-setter! uprog hyp-v hyp-f #:prefix "mix-"))))
(check-true (and (member ''"u_x" (sublists mix-setter-body)) #t))


;; ---------- 内建类型别名：interface / struct 表 / vertex-layout / uniform-setter ----------
(shader-struct alias-vertex (vec-3 model-pos) (vec-3 normal-vec))
(glsl-shader alias-vert
  (version 450 core)
  (layout (location 0) in vec-3 model-pos)
  (layout (location 1) in vec-3 normal-vec)
  (uniform mat-4 u-model-view)
  (uniform sampler-2d u-tex)
  (define (main) void))

(define alias-ifc (shader-program-interface alias-vert))
(check-equal? (map shader-var-name (shader-interface-vars alias-ifc))
              '(model-pos normal-vec u-model-view u-tex))
;; 反射里的类型名统一 canonical
(check-equal? (map (lambda (v) (shader-type-name (shader-var-type v)))
                   (shader-interface-vars alias-ifc))
              '(vec3 vec3 mat4 sampler2D))
;; <Name>-fields 也存 canonical 类型名
(check-equal? (alias-vertex-fields) '((model-pos vec3) (normal-vec vec3)))

(define alias-ex (syntax->datum (expand #'(glsl-vertex-layout! alias-vert alias-vertex))))
(check-true (and (member '(#%app gl-vertex-attrib-pointer '0 '3 gl-float '#f '24 '0)
                         (sublists alias-ex)) #t))
(check-true (and (member '(#%app gl-vertex-attrib-pointer '1 '3 gl-float '#f '24 '12)
                         (sublists alias-ex)) #t))

(glsl-uniform-setter! uprog alias-vert #:prefix "alias-")
(check-true (procedure? set-alias-u-model-view!))
(check-true (procedure? set-alias-u-tex!))
(define alias-setter-body
  (syntax->datum (expand #'(glsl-uniform-setter! uprog alias-vert #:prefix "alias-"))))
(check-true (and (member ''mat4 (sublists alias-setter-body)) #t))
(check-true (and (member ''sampler2D (sublists alias-setter-body)) #t))

;; 类型别名也能用于 uniform-type-supported?（编译期）
(check-true (uniform-type-supported? 'vec-3))
(check-true (uniform-type-supported? 'mat-4))
(check-true (uniform-type-supported? 'sampler-2d))

(displayln "meta 全部测试通过")
