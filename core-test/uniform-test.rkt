#lang racket/base

;; ============================================================
;; uniform-test.rkt —— uniform-set! 的名字可用性 + 校验路径（无需显示器）
;;
;; 只测「在调用 GL 之前就报错」的纯校验分支：
;;   非法 location / 未知类型 / 不支持的矩形矩阵 / 精度与分量数不符 / 纹理单元非整数。
;; 真正调用 glUniform* 需要 GL 上下文，留给带显示器的测试或教程运行。
;; ============================================================

(require rackunit
         glsl-opengl)

(check-true (procedure? uniform-set!))

;; location 必须是整数（uniform-location 的返回值）
(check-exn exn:fail? (lambda () (uniform-set! "not-int" 'float 1.0)))

;; 未知 GLSL 类型
(check-exn exn:fail? (lambda () (uniform-set! 0 'no-such-type 1)))

;; 矩形矩阵 / 结构等暂不支持，给清晰报错（而不是静默或崩溃）
(check-exn exn:fail? (lambda () (uniform-set! 0 'mat2x3 (f32vector))))

;; 向量：分量数 / 精度不符
(check-exn exn:fail? (lambda () (uniform-set! 0 'vec3 (vec2 1.0 2.0))))        ; 少一个分量
(check-exn exn:fail? (lambda () (uniform-set! 0 'vec3 (ivec3 1 2 3))))         ; 精度不符
(check-exn exn:fail? (lambda () (uniform-set! 0 'vec3 (vec4 1.0 2.0 3.0 4.0)))) ; 多一个分量

;; 标量：float 要 flonum，int 要整数（不做隐式转换）
(check-exn exn:fail? (lambda () (uniform-set! 0 'float 1)))
(check-exn exn:fail? (lambda () (uniform-set! 0 'int 1.0)))

;; 矩阵：标量个数错
(check-exn exn:fail? (lambda () (uniform-set! 0 'mat4 (vec4 1.0 2.0 3.0 4.0))))

;; 纹理单元必须是整数
(check-exn exn:fail? (lambda () (uniform-set! 0 'sampler2D 1.0)))

(displayln "uniform 全部检查通过")
