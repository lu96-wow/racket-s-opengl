#lang racket/base

;; ============================================================
;; gl · buffer.rkt —— 缓冲上传便捷层（Part 3.5）
;;
;; 「逻辑：把 vec-array / shader-struct 铺平结果 / 任意 ffi 向量 上传到 VBO / EBO」。
;;
;;   buffer-upload : glBufferData     （分配 + 拷贝）
;;   buffer-update : glBufferSubData  （局部更新；offset 是字节偏移）
;;
;; ★ 与 Racket GC 的关系（DESIGN.md §3.1）：
;;   外部 opengl 绑定的 _pointer/intptr 已经负责「Racket 向量 → 调用期 C 指针」，
;;   且 glBufferData / glBufferSubData 是同步拷贝——调用返回后 Racket 向量可被 GC 移动 / 回收。
;;   所以本层把向量**直接透传**，不自己转指针、不 pin、不缓存。
;;
;; ★ 不变量：本层绝不引入「GL 长期持有 Racket 侧指针」的调用（如 glMapBuffer 式常驻指针）。
;;   core-test/access-api-test.rkt 有一条可执行的 grep 约束守着这个不变量。
;; ============================================================

(require (only-in opengl gl-vector?)
         (only-in shader/value/buffer vec-buffer? vec-buffer-data)
         "../opengl/rename.rkt")   ; gl-buffer-data / gl-buffer-sub-data / gl-vector-sizeof / gl-static-draw

(provide buffer-upload buffer-update)

;; 归一成可直接交给 GL 绑定的 ffi 向量：
;;   vec-buffer（vec-array / dvec-array / ivec-array / uvec-array）→ 内部 data；
;;   ffi 向量（f32/f64/s32/u32/u16/s16/s8/bytes，即 gl-vector?）→ 原样透传。
(define (upload-data who data)
  (cond
    [(vec-buffer? data) (vec-buffer-data data)]
    [(gl-vector? data) data]
    [else (error who "需要 vec-array / vec-buffer 或 ffi 向量，实际 ~s" data)]))

;; 分配 + 拷贝到缓冲（对应 glBufferData）。
;;   target = gl-array-buffer / gl-element-array-buffer / …
;;   usage  缺省 gl-static-draw（还有 gl-stream-draw / gl-dynamic-draw）
(define (buffer-upload target data [usage gl-static-draw])
  (define d (upload-data 'buffer-upload data))
  (gl-buffer-data target (gl-vector-sizeof d) d usage))

;; 局部更新（对应 glBufferSubData）：offset 是字节偏移。
(define (buffer-update target offset data)
  (define d (upload-data 'buffer-update data))
  (gl-buffer-sub-data target offset (gl-vector-sizeof d) d))
