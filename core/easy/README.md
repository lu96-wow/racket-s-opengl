# Part 3.5 · easy/ —— GL 对象与取用便捷层

把「1:1 的 `gl-*`」包成「返回/接收单个句柄、直接吃 ffi 向量」的便利函数，
消掉教程里大量 `(u32vector-ref (gl-gen-buffers 1) 0)` 与手动 `glBufferData` 样板。

| 逻辑 | 文件 | 典型名字 |
|---|---|---|
| GL 对象句柄（分配 / 删除） | `object.rkt` | 单句柄：`buffer-new` / `texture-new` / `vertex-array-new` / `framebuffer-new` / `renderbuffer-new`；多句柄：`buffers-new` / `textures-new` / `vertex-arrays-new` / `framebuffers-new` / `renderbuffers-new`（以及 `*-delete`）；多值版：`*-new/values` |
| 缓冲上传 | `buffer.rkt` | `buffer-upload`、`buffer-update` |
| uniform 上传 | `uniform.rkt` | `uniform-set!`（按 GLSL 类型符号分派；接受 `vec-3` / `mat-4` / `sampler-2d` 等别名） |

## 命名（见 [../../DESIGN.md](../../DESIGN.md)）

**不用 `gl-*`**——`gl-*` 只给 OpenGL C 符号的 1:1 机械映射，而 `glGenBuffer` 这个符号并不存在。
本层走工具层的 `<资源>-<动词>`：`buffer-new` / `buffer-delete`（同 `shader-compile` / `program-link`）。
`gl-gen-*` / `gl-delete-*` 等 raw 名**原样保留**；便利层另外提供复数版：

```racket
(buffers-new 4)              ; => u32vector，4 个 buffer id
(textures-new 8)             ; => u32vector，8 个 texture id
(vertex-arrays-new 2)        ; => u32vector，2 个 VAO id
(framebuffers-new 2)         ; => u32vector，2 个 FBO id
(renderbuffers-new 2)        ; => u32vector，2 个 RBO id

(buffers-delete ids)         ; 接受 u32vector 或 id 列表
(textures-delete ids)        ; 同上
```

单句柄用 `<资源>-new` / `<资源>-delete`，多句柄用 `<资源复数>-new` / `<资源复数>-delete`；返回类型不会在“单个 id”和“id 向量”之间摇摆。

固定数量也可以直接用多值版：

```racket
(define-values (vbo ebo) (buffers-new/values 2))
(define-values (tex0 tex1 tex2 tex3) (textures-new/values 4))
```

动态数量仍用向量版；`define-values` 的绑定个数在编译期就定死了。

## 生命周期与 Racket GC（关键约定）

- 句柄是**裸 `GLuint`**，不挂终结器、不做自动回收。GL 删除必须在「拥有该对象的上下文所在线程」
  执行，而 Racket 终结器在 GC 线程/不确定时机运行；且 program↔shader 之类依赖的释放顺序不保证。
- **所有权**：`*-new` 返回的句柄归调用方，用完自行 `*-delete`。
- `buffer-upload` / `buffer-update` 只读入参、不保留引用。GL 调用是**同步拷贝**，
  返回后 Racket 向量可被 GC 移动/回收。
- **不变量**：本层绝不引入「GL 长期持有 Racket 侧指针」的调用（如 `glMapBuffer` 式常驻指针）。
  由 `core-test/access-api-test.rkt` 的可执行 grep 约束守着。

详见 [../../DESIGN.md](../../DESIGN.md) §3.1。

## 依赖

只组合两样东西：raw `gl-*`（`../opengl/rename.rkt` + 外部 `opengl`）和值层（`glsl/core/value/*`）。
类型别名规范化来自共享词汇模块 `glsl/core/vocab/type-names`（不是语言层 `core/glsl/*`）。
**不** require `glsl/core/glsl/*`（GLSL 语言文本）或 `core/tool/*`（胶水）——
边界由 `core-test/access-api-test.rkt` 的第二条约束守着。
