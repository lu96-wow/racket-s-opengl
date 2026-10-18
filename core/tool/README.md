# 胶水 · tool/ —— 把两块接起来（编译 / 链接 / 报错）

这里不属于「GLSL 语言」也不属于「OpenGL rename」，它是**唯一的组合点**：
用 Part 1 产出的 GLSL 文本 + Part 3 的 `gl-*` 名字，去和 GL 驱动打交道。

| 逻辑 | 文件 | 所在包 | 状态 |
|---|---|---|---|
| 编译：GLSL 文本 → shader（+ 三段式报错） | `compile.rkt` | racket-shader-opengl | ✅ |
| 链接 / program 生命周期（link/build/use/uniform/delete） | `program.rkt` | racket-shader-opengl | ✅ |
| 报错的解析 / 定位 / 渲染（纯函数） | `shader/error.rkt` | racket-shader | ✅ |

内部依赖：`program.rkt` → `compile.rkt` → `shader/error` → `shader/program`。
跨包依赖（collection 路径）：`glsl/{pretty,program}`、`shader/error`；
本包内：`../opengl/rename.rkt`（`gl-*`）＋外部 `opengl` 包。

> 注意：本目录的 `program.rkt` 是 **GL program 生命周期**，与 `glsl/program.rkt`（`glsl-program` 产物）不是一回事。
