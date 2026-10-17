#lang racket/base

;; ============================================================
;; meta · table.rkt —— 编译期表读取助手
;;
;; 纯包的 define 宏把「编译期表」绑成宏（展开为 (quote 数据)）；
;; 消费宏（如 vertex-layout / uniform-setter）用本助手 local-expand 后取出数据。
;; ============================================================

(provide table-datum)

;; 宏（编译期表）→ 其 quote 数据；(quote d) / (#%quote d) 都认。
(define (table-datum who id)
  (define d (syntax->datum (local-expand id 'expression '())))
  (unless (and (pair? d) (memq (car d) '(quote #%quote)) (= 2 (length d)))
    (error who "~a 不是编译期表（应为宏展开成 quote 数据）" (syntax->datum id)))
  (cadr d))
