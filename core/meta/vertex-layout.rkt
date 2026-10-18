#lang racket/base

;; ============================================================
;; meta · vertex-layout.rkt —— 表驱动的顶点布局代码生成（编译期，按名字对齐）
;;
;; 「逻辑：读 shader 的编译期接口表 + CPU 侧 struct 的编译期字段表，
;;   按 **名字** 自动对齐（对称标识符），在展开期直接生成 gl-* 调用」。
;;
;;   (shader-struct vertex (vec3 pos) (vec3 normal))              ; 字段名
;;   (glsl-shader vert  (layout (location 0) in vec3 pos) …)    ; 属性名 = 字段名
;;   (glsl-vertex-layout! vert vertex)
;;   ;; 展开为字面量（无运行期查表）：
;;   (gl-vertex-attrib-pointer 0 3 gl-float #f 24 0) (gl-enable-vertex-attrib-array 0)
;;   (gl-vertex-attrib-pointer 1 3 gl-float #f 24 12) (gl-enable-vertex-attrib-array 1)
;;
;; - **按名字 join**：字段 `pos` ↔ shader `in pos`；两边顺序可不同。
;; - 编译期校验：字段缺 in / in 缺字段 / 类型不符 → 展开期报错。
;; - slot 取自 shader 的 layout(location)；分量/GL 类型/stride/offset 取自字段表。
;; - 精度分派：f32→-pointer、f64→-l-pointer、s32/u32→-ip-pointer。
;;
;; 分层：本宏属 opengl 包的 meta 层；表由纯包产出（glsl-shader / shader-struct）。
;; 只在有 gl-* 的模块里用（#lang glsl-opengl）。裸写 conflig 仍可用——本宏是可选扩展。
;; ============================================================

(require (for-syntax racket/base
                     racket/list
                     racket/syntax
                     "table.rkt"
                     (only-in shader/value/type type-elements type-kind type-byte-size)
                     (only-in shader/interface
                              datum->shader-interface shader-interface-vars)
                     (only-in shader/type
                              shader-var-name shader-var-qualifiers shader-var-layout-ref shader-var-type
                              shader-type-name)
                     (only-in glsl/names glsl-name-symbol)
                     (only-in shader/types type-canonical-symbol)))

(provide glsl-vertex-layout!)

(begin-for-syntax

  ;; 属性精度 → (gl 指针函数, gl 类型枚举)
  (define (pointer-and-enum kind)
    (case kind
      [(f32) (values 'gl-vertex-attrib-pointer 'gl-float)]
      [(f64) (values 'gl-vertex-attrib-l-pointer 'gl-double)]
      [(s32) (values 'gl-vertex-attrib-ip-pointer 'gl-int)]
      [(u32) (values 'gl-vertex-attrib-ip-pointer 'gl-unsigned-int)]
      [else (error 'glsl-vertex-layout! "不支持的属性精度 ~a" kind)])))

(define-syntax (glsl-vertex-layout! stx)
  (syntax-case stx ()
    [(_ shader-name struct-name)
     (and (identifier? #'shader-name) (identifier? #'struct-name))
     (let ()
       (define iface-id (format-id #'shader-name "~a-interface" #'shader-name))
       (define fields-id (format-id #'struct-name "~a-fields" #'struct-name))
       (define iface (datum->shader-interface (table-datum 'glsl-vertex-layout! iface-id)))
       (define fields (table-datum 'glsl-vertex-layout! fields-id))   ; ((field type) ...)

       ;; shader 的 in 变量：按名字建索引；必须都有显式 location
       (define in-vars
         (for/list ([v (in-list (shader-interface-vars iface))]
                    #:when (memq 'in (shader-var-qualifiers v)))
           v))
       (for ([v (in-list in-vars)])
         (unless (shader-var-layout-ref v 'location)
           (error 'glsl-vertex-layout! "shader 的 in 变量 ~a 缺少 layout(location)"
                  (shader-var-name v))))
       ;; 按 **GLSL 名** 建索引：model-pos 与 model_pos 视为同一个属性。
       (define in-by-name (make-hash))
       (for ([v (in-list in-vars)])
         (define g (glsl-name-symbol (shader-var-name v)))
         (when (hash-ref in-by-name g #f)
           (error 'glsl-vertex-layout! "shader 的 in ~a 与 ~a 都会生成 GLSL 标识符 ~a"
                  (shader-var-name (hash-ref in-by-name g)) (shader-var-name v) g))
         (hash-set! in-by-name g v))

       ;; CPU struct 字段也按 GLSL 名检查重复
       (define field-names
         (let loop ([fs fields] [seen '()] [acc '()])
           (cond
             [(null? fs) (reverse acc)]
             [else
              (define fn (caar fs))
              (define g (glsl-name-symbol fn))
              (when (memq g seen)
                (error 'glsl-vertex-layout! "struct 字段 ~a 与已有字段都会生成 GLSL 标识符 ~a" fn g))
              (loop (cdr fs) (cons g seen) (cons g acc))])))

       ;; 逐字段：按 GLSL 名找 in；缺 in / 类型不符 → 编译期报错
       (for ([f (in-list fields)])
         (define fn (car f))
         (define ft (type-canonical-symbol (cadr f)))
         (define fg (glsl-name-symbol fn))
         (define v (hash-ref in-by-name fg #f))
         (unless v
           (error 'glsl-vertex-layout! "struct 字段 ~a（GLSL 名 ~a）在 shader 的 in 里没有对应属性"
                  fn fg))
         (define st (shader-type-name (shader-var-type v)))
         (unless (eq? st ft)
           (error 'glsl-vertex-layout! "字段 ~a 类型 ~a 与 shader in ~a 类型 ~a 不匹配"
                  fn ft (shader-var-name v) st)))
       ;; 反向：shader 的 in 有没有多余属性
       (for ([v (in-list in-vars)])
         (unless (memq (glsl-name-symbol (shader-var-name v)) field-names)
           (error 'glsl-vertex-layout! "shader 的 in ~a 在 struct 里没有对应字段"
                  (shader-var-name v))))

       ;; 逐字段：offset 累计（按 struct 顺序铺平）；stride = 总字节
       (define offsets
         (let loop ([fs fields] [off 0] [acc '()])
           (cond [(null? fs) (reverse acc)]
                 [else (loop (cdr fs) (+ off (type-byte-size (cadr (car fs)))) (cons off acc))])))
       (define stride (for/fold ([off 0]) ([f (in-list fields)]) (+ off (type-byte-size (cadr f)))))

       ;; 生成：按 struct 字段顺序 emit；location 取自同名的 shader in
       (define calls
         (append*
          (for/list ([f (in-list fields)] [off (in-list offsets)])
            (define ft (cadr f))
            (define kind (type-kind ft))
            (define-values (ptr glenum) (pointer-and-enum kind))
            (define loc (shader-var-layout-ref (hash-ref in-by-name (glsl-name-symbol (car f))) 'location))
            (define comps (type-elements ft))
            (list (if (eq? kind 'f32)
                      (list ptr loc comps glenum #f stride off)   ; float 有 normalized 参数
                      (list ptr loc comps glenum stride off))      ; ip/l 指针无 normalized
                  (list 'gl-enable-vertex-attrib-array loc)))))

       (datum->syntax stx (cons 'begin calls)))]))
