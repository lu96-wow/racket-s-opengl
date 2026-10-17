# Part 3 · opengl/ —— OpenGL → Racket 风格命名（独立块）

| 逻辑 | 文件 | 状态 |
|---|---|---|
| OpenGL C API → Racket 命名 | `rename.rkt` | ✅ 纯机械 1:1 映射（函数） |
| 常量全量表（生成文件） | `constants.rkt` | ✅ 覆盖 `opengl` 全部 `GL_*` |
| 常量表生成器 | `generate-constants.rkt` | ✅ 重新生成 `constants.rkt` |
| 语义别名（名字更准确） | `alias.rkt` | ✅ 只加别名，不改行为 |

`rename.rkt` 是**纯机械映射**，只认外部 `opengl` 包的 C 名字，不需要知道 GLSL、也不需要知道值层：

- 函数：`glGenBuffers` → `gl-gen-buffers`
- 常量：`GL_ARRAY_BUFFER` → `gl-array-buffer`
- 冲突例外：`GL_CULL_FACE` → `var-cull-face`（避开与函数 `gl-cull-face` 撞名）
- 常量全量表在 `constants.rkt`（生成文件，勿手改）；`opengl` 更新后运行
  `racket core/opengl/generate-constants.rkt` 重新生成。

编译 / 链接 / 报错不在这里，在 `tool/`（因为它要同时用到 GLSL 文本，属于组合）。
