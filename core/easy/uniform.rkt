#lang racket/base

;; ============================================================
;; gl · uniform.rkt —— uniform 上传便捷层（Part 3.5，P3a）
;;
;; 「逻辑：按 GLSL 类型符号把 CPU 值上传到 uniform，省掉 gl-uniform-* 的样板」。
;;
;;   (uniform-set! loc 'mat4 m)     ; 原 (gl-uniform-matrix-4fv loc 1 #f m)
;;   (uniform-set! loc 'vec3 v)     ; 原 (gl-uniform-3f loc (vx v) (vy v) (vz v))
;;   (uniform-set! loc 'float x)    ; 原 (gl-uniform-1f loc x)
;;   (uniform-set! loc 'int i)      ; 原 (gl-uniform-1i loc i)
;;   (uniform-set! loc 'sampler2D t); 原 (gl-uniform-1i loc t)
;;
;; 类型符号直接取自值层 / interface 的 GLSL 类型名目录（同名键），不另造表。
;; 类型别名（vec-3 / mat-4 / sampler-2d …）会先规范成 canonical（vec3 / mat4 / sampler2D）。
;; loc 由 (uniform-location prog "name") 得到（找不到返回 -1，OpenGL 约定）。
;;
;; 命名：工具层 <资源>-<动词>（uniform-set!），不带 gl-*，不与 raw 层同基名。
;; 覆盖：标量、vec/ivec/uvec/bvec/dvec、方阵 mat/dmat、sampler*/image*。
;;       矩形矩阵（matCxR）与 struct/数组 uniform 暂不支持，请用 raw gl-uniform-*。
;; ============================================================

(require (only-in glsl/core/value/type type-known? type-kind type-elements kind->name)
         (only-in glsl/core/value/cvector value-kind)
         (only-in glsl/core/value/access vec-count vec-ref)
         (only-in glsl/core/vocab/type-names glsl-type-canonical-symbol)
         "../opengl/rename.rkt")

(provide uniform-set! uniform-type-supported?)

;; ---------- 输入校验小工具 ----------

(define (flonum* who x)
  (unless (flonum? x) (error who "需要浮点数（如 1.0），实际 ~s" x))
  x)

(define (exact-int* who x)
  (unless (and (exact? x) (integer? x)) (error who "需要整数，实际 ~s" x))
  x)

;; ---------- 上传器构造 ----------

;; 标量
(define (fscalar raw) (lambda (loc _type v) (raw loc (flonum* 'uniform-set! v))))
(define (iscalar raw) (lambda (loc _type v) (raw loc (exact-int* 'uniform-set! v))))
(define (bscalar raw) (lambda (loc _type v) (raw loc (if v 1 0))))

;; 向量：按 type 校验精度 + 分量数，再拆成分量调用 gl-uniform-N*
(define (components who type v)
  (define expected (type-kind type))
  (define actual (value-kind v who))
  (unless (eq? expected actual)
    (error who "~a 需要 ~a 向量，实际 ~a" type (kind->name expected) (kind->name actual)))
  (define n (type-elements type))
  (unless (= n (vec-count v))
    (error who "~a 需要 ~a 个分量，实际 ~a" type n (vec-count v)))
  (for/list ([i (in-range n)]) (vec-ref v i)))

(define (vec-uploader raw)
  (lambda (loc type v) (apply raw loc (components 'uniform-set! type v))))

;; 方阵：transpose 固定 #f（本库矩阵就是列主序，与 uniform 布局一致）
(define (matrix-uploader raw n)
  (lambda (loc type m)
    (define expected (type-kind type))
    (define actual (value-kind m 'uniform-set!))
    (unless (eq? expected actual)
      (error 'uniform-set! "~a 需要 ~a 矩阵，实际 ~a" type (kind->name expected) (kind->name actual)))
    (unless (= (* n n) (vec-count m))
      (error 'uniform-set! "~a 需要 ~a 个标量，实际 ~a" type (* n n) (vec-count m)))
    (raw loc 1 #f m)))

;; ---------- 类型符号 → 上传器 ----------

(define uploaders
  (hash
   ;; 标量
   'float  (fscalar gl-uniform-1f)
   'double (fscalar gl-uniform-1d)
   'int    (iscalar gl-uniform-1i)
   'uint   (iscalar gl-uniform-1ui)
   'bool   (bscalar gl-uniform-1i)
   ;; float 向量
   'vec2 (vec-uploader gl-uniform-2f)
   'vec3 (vec-uploader gl-uniform-3f)
   'vec4 (vec-uploader gl-uniform-4f)
   ;; double 向量
   'dvec2 (vec-uploader gl-uniform-2d)
   'dvec3 (vec-uploader gl-uniform-3d)
   'dvec4 (vec-uploader gl-uniform-4d)
   ;; int 向量
   'ivec2 (vec-uploader gl-uniform-2i)
   'ivec3 (vec-uploader gl-uniform-3i)
   'ivec4 (vec-uploader gl-uniform-4i)
   ;; uint 向量
   'uvec2 (vec-uploader gl-uniform-2ui)
   'uvec3 (vec-uploader gl-uniform-3ui)
   'uvec4 (vec-uploader gl-uniform-4ui)
   ;; bool 向量（内存是 32 位 0/1，走整型上传）
   'bvec2 (vec-uploader gl-uniform-2i)
   'bvec3 (vec-uploader gl-uniform-3i)
   'bvec4 (vec-uploader gl-uniform-4i)
   ;; 方阵
   'mat2  (matrix-uploader gl-uniform-matrix-2fv 2)
   'mat3  (matrix-uploader gl-uniform-matrix-3fv 3)
   'mat4  (matrix-uploader gl-uniform-matrix-4fv 4)
   'dmat2 (matrix-uploader gl-uniform-matrix-2dv 2)
   'dmat3 (matrix-uploader gl-uniform-matrix-3dv 3)
   'dmat4 (matrix-uploader gl-uniform-matrix-4dv 4)))

;; sampler* / isampler* / usampler* / image* / iimage* / uimage*
(define (sampler-or-image? type)
  (and (symbol? type)
       (regexp-match? #rx"^(i|u)?(sampler|image)" (symbol->string type))))

;; 该 GLSL 类型能否用 uniform-set! 上传（供宏在编译期判断，决定是否为它生成 setter）
(define (uniform-type-supported? type)
  (and (or (symbol? type) (string? type))
       (let ([type* (glsl-type-canonical-symbol type)])
         (or (sampler-or-image? type*)
             (and (type-known? type*) (hash-ref uploaders type* #f) #t)))))

;; ---------- 入口 ----------

(define (uniform-set! loc type value)
  (unless (exact-integer? loc)
    (error 'uniform-set! "location 应为整数（uniform-location 的返回值），实际 ~s" loc))
  ;; 类型别名（vec-3 / mat-4 / sampler-2d …）先规范成 canonical
  (define type* (glsl-type-canonical-symbol type))
  (cond
    [(sampler-or-image? type*)
     (unless (exact-integer? value)
       (error 'uniform-set! "~a 纹理单元应为整数，实际 ~s" type* value))
     (gl-uniform-1i loc value)]
    [(type-known? type*)
     (define up (hash-ref uploaders type* #f))
     (unless up
       (error 'uniform-set! "uniform-set! 暂不支持类型 ~a（矩形矩阵/结构/数组请用 raw gl-uniform-*）" type*))
     (up loc type* value)]
    [else
     (error 'uniform-set! "未知 GLSL 类型 ~s" type)]))
