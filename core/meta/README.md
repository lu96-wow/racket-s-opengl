# Part 4 · meta/ —— 表驱动的编译期代码生成

消费**纯包产出的编译期表**，在 Racket 宏展开期直接生成 `gl-*` 调用（字面量，无运行期查表）。

| 逻辑 | 文件 | 名字 |
|---|---|---|
| 顶点布局 | `vertex-layout.rkt` | `glsl-vertex-layout!` |
| uniform setter | `uniform-setter.rkt` | `glsl-uniform-setter!` |
| 编译期表读取助手（内部） | `table.rkt` | `table-datum` |

## 表的来源（纯包产出）

| 表 | 谁产出 | 绑定 |
|---|---|---|
| shader 接口表 | `(glsl-shader name …)` | `<name>-interface`（宏，展开为 `(quote <iface-datum>)`） |
| CPU 字段表 | `(glsl-struct Name (类型 字段) …)` | `<Name>-fields`（宏，展开为 `(quote ((字段 类型) …))`） |

两者都是**纯数据、可 `quote`**，供宏 `local-expand` 后读取。

## `glsl-vertex-layout!`

```racket
(glsl-struct vertex (vec3 pos) (vec3 normal) (vec2 uv))
(glsl-shader vert
  (version 330 core)
  (layout (location 0) in vec3 pos)       ; 属性名 = struct 字段名
  (layout (location 1) in vec3 normal)
  (layout (location 2) in vec2 uv)
  (define (main) void))

(define (init)
  (glsl-vertex-layout! vert vertex))
;; 展开为（编译期生成的字面量）：
(gl-vertex-attrib-pointer 0 3 gl-float #f 32 0) (gl-enable-vertex-attrib-array 0)
(gl-vertex-attrib-pointer 1 3 gl-float #f 32 12) (gl-enable-vertex-attrib-array 1)
(gl-vertex-attrib-pointer 2 2 gl-float #f 32 24) (gl-enable-vertex-attrib-array 2)
```

- slot 取自 shader 的 `layout(location N)`；分量数/GL 类型/stride/offset 取自字段表；
- **按名字自动对齐**：字段 `pos` ↔ shader `in pos`；两边顺序可不同；
  比较的是归一后的 GLSL 标识符（CPU `model-pos` ↔ shader `in model_pos` 也能对上）；
- 类型别名（`vec-3` / `mat-4` / `sampler-2d` …）在 shader 接口和 CPU `<Name>-fields` 里
  都统一成 canonical（`vec3` / `mat4` / `sampler2D`），所以类型比较不需要另做映射；
- **编译期校验**：字段缺 in / in 缺字段 / 类型不符 → **展开期报错**；
- 精度分派：`f32`→`gl-vertex-attrib-pointer`、`f64`→`-l-pointer`、`s32/u32`→`-ip-pointer`。

## 依赖边界

- 编译期依赖纯包：`glsl/core/glsl/interface`（接口表）、`glsl/core/value/type`（类型→分量/字节）。
- 运行期 emit 的是 `gl-*`，故**只能在有 `gl-*` 的模块里用**（`#lang glsl-opengl`）。
- 本层不 require `core/tool/`、不 require 运行期 `core/easy/`。

## `glsl-uniform-setter!`

`(glsl-uniform-setter! program-id shader-name ... [#:prefix pfx])`
按 shader 的**编译期接口表**，为每个 uniform 生成 `set-<前缀><名字>!`（类型从接口推、名字无需手写）。

```racket
(glsl-shader vert-src (version 330 core) (uniform mat4 uMVP) (uniform mat3 uNormalMatrix))
(glsl-shader frag-src (version 330 core) (uniform vec3 uLightColor))
(define prog (build-program (gl-vertex-shader vert-src) (gl-fragment-shader frag-src)))

(glsl-uniform-setter! prog vert-src frag-src #:prefix "obj-")
;; =>
(define (set-obj-uMVP! v)          (uniform-set! (uniform-location prog "uMVP") 'mat4 v))
(define (set-obj-uNormalMatrix! v) (uniform-set! (uniform-location prog "uNormalMatrix") 'mat3 v))
(define (set-obj-uLightColor! v)   (uniform-set! (uniform-location prog "uLightColor") 'vec3 v))
```

- **program 在前**：运行期 program（setter 闭包引用它）；后面跟 1 个或多个 shader（提供编译期接口表）。
- **多 stage**：合并各 shader 的 uniform；同名要求类型一致（否则编译期报错）。
- **`#:prefix`**：多 program 时避免同名 uniform 撞。
- **按名字**：拼错 uniform 名 → 未绑定标识符（编译错误），不再静默 `-1`；
- **推类型**：类型符号取自接口，无需手写；
- 只给 `uniform-set!` 支持的类型（标量/向量/矩阵/sampler/image）生成；struct/block/数组跳过，仍可用 `gl-uniform-*` 手写。
- **扩展不取代基础**：`uniform-set!` / 裸 `gl-uniform-*` / `(glsl …)` 均不受影响。
- **连字符名**：setter 的 Racket 名字用表面名（`(uniform mat4 u-model-view)` → `set-u-model-view!`），
  `uniform-location` 用 GLSL 名（`"u_model_view"`）；多 stage 的 `u-x` / `u_x` 视为同一个
  uniform，按第一次出现的表面名生成 setter。
- **类型别名**：`(uniform mat-4 u-m)` / `(uniform sampler-2d u-tex)` 会从接口拿到 canonical
  `mat4` / `sampler2D`，生成的 setter 直接用 `uniform-set!` 支持的类型符号。
