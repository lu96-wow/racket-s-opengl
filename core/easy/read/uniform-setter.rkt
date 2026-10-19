#lang racket/base

;; ============================================================
;; meta · uniform-setter.rkt —— 按名字 + 接口推类型，生成 uniform setter（编译期）
;;
;;   ;; 单 stage：
;;   (glsl-shader shader (version 330 core) (uniform mat4 uMVP) (uniform float uTime))
;;   (glsl-uniform-setter! prog shader)
;;   ;; 多 stage（vertex + fragment 的 uniform 并集）：
;;   (glsl-uniform-setter! prog vert-src frag-src #:prefix "obj-")
;;   ;; 展开为：
;;   (define (set-uMVP! v) (uniform-set! (gl-get-uniform-location prog "uMVP") 'mat4 v))
;;   (define (set-uTime! v) (uniform-set! (gl-get-uniform-location prog "uTime") 'float v))
;;
;; - **签名**：`(glsl-uniform-setter! program-id shader-name ... [#:prefix pfx])`
;;   program-id = 运行期 program（setter 闭包引用它）；shader-name... = 提供编译期接口表。
;; - **多 stage**：合并各 shader 的 uniform；同名要求类型一致（否则编译期报错）。
;; - 名字/类型都取自接口表：拼错名字 → 未绑定标识符（编译错误）；类型不用手写。
;; - 只给 uniform-set! 支持的类型生成（标量/向量/矩阵/sampler/image）；struct/block/数组跳过。
;; - **可选扩展**：不影响 uniform-set!、gl-uniform-*、裸 (glsl …)。
;; ============================================================

(require "../uniform.rkt"          ; 运行期：uniform-set!
         "../../opengl/rename.rkt"        ; 运行期：gl-get-uniform-location（不引胶水层）
         (for-syntax racket/base
                     racket/list
                     racket/syntax
                     "table.rkt"
                     "../uniform.rkt"   ; 编译期：uniform-type-supported?
                     (only-in shader/interface
                              datum->shader-interface shader-interface-vars)
                     (only-in shader/type
                              shader-var-name shader-var-source-name
                              shader-var-type shader-var-has-qualifier? shader-type-name)))

(provide glsl-uniform-setter!)

(define-syntax (glsl-uniform-setter! stx)

  ;; 合并若干 shader 的接口表 → 有序的 (surface-name glsl-name type) 列表
  ;;   - 去重按 **GLSL 名**（u-color 与 u_color 是同一个 uniform）；
  ;;   - setter 的 Racket 名字取第一次出现的 **表面名**（保持连字符风格）；
  ;;   - 同名 uniform 在不同 stage 类型冲突 → 编译期报错。
  (define (collect-uniforms ctx shader-ids)
    (define by-name (make-hash))
    (define order '())
    (for ([s (in-list shader-ids)])
      (define iface (datum->shader-interface (table-datum 'glsl-uniform-setter!
                                                        (format-id ctx "~a-interface" s))))
      (for ([v (in-list (shader-interface-vars iface))]
             #:when (shader-var-has-qualifier? v 'uniform))
        (define surface (shader-var-name v))
        (define glsl-nm (shader-var-source-name v))
        (define ty (shader-type-name (shader-var-type v)))
        (cond
          [(hash-ref by-name glsl-nm #f)
           => (lambda (prev)
                (define prev-ty (caddr prev))
                (unless (eq? prev-ty ty)
                  (error 'glsl-uniform-setter!
                         "uniform ~a（GLSL 名 ~a）在不同 stage 类型不一致：~a vs ~a"
                         surface glsl-nm prev-ty ty)))]
          [else
           (hash-set! by-name glsl-nm (list surface glsl-nm ty))
           (set! order (cons glsl-nm order))])))
    (for/list ([g (in-list (reverse order))]) (hash-ref by-name g)))

  ;; 生成一批 setter（pfx-str 为空则 `set-<名>!`，否则 `set-<pfx><名>!`）
  ;; setter 名 / 错误信息用表面名；gl-get-uniform-location 用 GLSL 名。
  (define (build ctx program-id shader-ids pfx-str)
    (define entries (collect-uniforms ctx shader-ids))
    (define items
      (for/list ([e (in-list entries)]
                 #:when (uniform-type-supported? (caddr e)))
        (list (format-id ctx "set-~a~a!" pfx-str (car e))
              (datum->syntax ctx (caddr e))
              (datum->syntax ctx (symbol->string (cadr e))))))
    (with-syntax ([program-id program-id]
                  [(setter ...) (map car items)]
                  [(ty ...) (map cadr items)]
                  [(nm ...) (map caddr items)])
      #'(begin
          (define (setter v)
            (uniform-set! (gl-get-uniform-location program-id nm) 'ty v))
          ...)))

  (syntax-case stx ()
    [(_ program-id shader-name ... #:prefix pfx)
     (and (identifier? #'program-id) (andmap identifier? (syntax->list #'(shader-name ...)))
          (pair? (syntax->list #'(shader-name ...))))
     (let ()
       (define d (syntax->datum #'pfx))
       (build stx #'program-id (syntax->list #'(shader-name ...))
              (if (symbol? d) (symbol->string d) d)))]
    [(_ program-id shader-name ...)
     (and (identifier? #'program-id) (andmap identifier? (syntax->list #'(shader-name ...)))
          (pair? (syntax->list #'(shader-name ...))))
     (build stx #'program-id (syntax->list #'(shader-name ...)) "")]))
