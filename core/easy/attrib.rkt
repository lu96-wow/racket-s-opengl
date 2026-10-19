#lang racket/base

;; ============================================================
;; easy · attrib.rkt —— 顶点属性的编译期计算
;;
;; 「逻辑：把 (字段名 类型) 列表变成一组 gl-vertex-attrib-* 调用所需的数字」。
;;   location 由调用方给（读模式：已有 GLSL 的 layout(location N)）；
;;   其余（分量数、GL 类型枚举、指针函数、normalized 参数、stride、offset）由类型算出。
;;   生成模式重新设计时，同样可以复用这里的数字计算，只是 location 来源不同。
;;
;; 提供：
;;   attrib-shape : type -> (values 指针函数 GL 类型枚举 是否有 normalized 参数)
;;   attrib-plan  : ((name type) ...) locs -> (values stride ((loc comps enum ptr norm? off) ...))
;;   attrib-calls : plan stride -> 展开用的 datum 列表（每项两条调用）
;;
;; 只在编译期用：消费方 require (for-syntax "attrib.rkt")。
;; 本模块不 require GLSL 方言层、也不 require 胶水层 —— 它只做数字。
;; ============================================================

(require racket/list
         (only-in shader/value/type type-elements type-kind type-byte-size))

(provide attrib-shape attrib-plan attrib-calls)

;; 类型精度 → (指针函数, GL 类型枚举, 有没有 normalized 参数)
;;   float 的 glVertexAttribPointer 带 normalized；整型走 -ip-、double 走 -l-，都没有这个参数。
(define (attrib-shape type)
  (case (type-kind type)
    [(f32) (values 'gl-vertex-attrib-pointer    'gl-float        #t)]
    [(f64) (values 'gl-vertex-attrib-l-pointer  'gl-double       #f)]
    [(s32) (values 'gl-vertex-attrib-ip-pointer 'gl-int          #f)]
    [(u32) (values 'gl-vertex-attrib-ip-pointer 'gl-unsigned-int #f)]
    [else (error 'attrib-shape "不支持的属性精度 ~a" (type-kind type))]))

;; 按 struct 顺序铺平：offset 依次累加，stride = 总字节数。
;;   locs 与 fields 等长；读模式传 shader 的 location，生成模式传 0..n-1。
(define (attrib-plan fields locs)
  (unless (= (length fields) (length locs))
    (error 'attrib-plan "字段数 ~a 与 location 数 ~a 不一致"
           (length fields) (length locs)))
  (define stride
    (for/fold ([off 0]) ([f (in-list fields)])
      (+ off (type-byte-size (cadr f)))))
  (define plan
    (let loop ([fs fields] [ls locs] [off 0] [acc '()])
      (cond
        [(null? fs) (reverse acc)]
        [else
         (define f (car fs))
         (define-values (ptr enum norm?) (attrib-shape (cadr f)))
         (define item (list (car ls) (type-elements (cadr f)) enum ptr norm? off))
         (loop (cdr fs) (cdr ls) (+ off (type-byte-size (cadr f))) (cons item acc))])))
  (values stride plan))

;; plan → 两组调用：设指针 + 打开槽。返回值是 datum，由调用宏 datum->syntax 出去。
(define (attrib-calls plan stride)
  (append*
   (for/list ([item (in-list plan)])
     (define-values (loc comps enum ptr norm? off) (apply values item))
     (list (if norm?
               (list ptr loc comps enum #f stride off)      ; (loc comps type normalized stride offset)
               (list ptr loc comps enum stride off))        ; 无 normalized 参数
           (list 'gl-enable-vertex-attrib-array loc)))))
