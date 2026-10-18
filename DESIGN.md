# racket-shader-opengl · 设计与逻辑分层

本包 = **Part 3（OpenGL → Racket 1:1 映射）+ Part 3.5（便利层）+ 胶水（编译/链接）**。

**单向依赖** [`racket-shader`](../racket-shader/DESIGN.md)：本包 require 纯包，反向不成立。
纯包不含任何 `opengl` 引用。

---

## 1. 逻辑分层

```
racket-shader-opengl/
  core/opengl/rename.rkt          Part 3   函数 1:1 映射（gl-*）——纯机械，无逻辑
  core/opengl/constants.rkt       Part 3   GL_* 常量全量表（生成文件）
  core/opengl/generate-constants.rkt      生成 constants.rkt
  core/easy/{object,buffer,uniform}.rkt   Part 3.5 便利层——组合 raw gl + 值层（运行期）
  core/meta/vertex-layout.rkt     Part 4   表驱动的编译期代码生成（宏）
  core/tool/{compile,program}.rkt         胶水——把 GLSL 文本编成 GL 对象
```

| 层 | 输入 | 输出 | 命名 |
|---|---|---|---|
| Part 3 `core/opengl/` | OpenGL C 符号 | Racket kebab 名 | `gl-*` |
| Part 3.5 `core/easy/` | raw `gl-*` + 值层 | 组合操作（运行期） | `<资源>-<动词>` |
| Part 4 `core/meta/` | 纯包编译期表 | 生成 `gl-*` 调用（展开期） | `glsl-*`（消费表） |
| 胶水 `core/tool/` | GLSL **文本**（`glsl/*`） | shader / program | `<资源>-<动词>` |

三条线互不缠绕——`easy/` 不碰 GLSL 文本，`tool/` 目前不 require `easy/`。

### 依赖边界（由测试约束）

- `core/easy/*` **可** require：`shader/value/*`、`../opengl/rename.rkt`、外部 `opengl`。
- `core/easy/*` **不可** require：`glsl/*`（语言文本）、`core/tool/*`。
- `core/tool/*` 可 require `glsl/*` + `core/opengl/*`。

约束落在 `core-test/access-api-test.rkt`（grep 源码）。

---

## 2. Part 3 · `core/opengl/rename.rkt` —— 1:1 映射

`opengl` 包的 C 名字改成 Racket kebab-case，**只做机械映射、不发明**：

- 函数：`glGenBuffers` → `gl-gen-buffers`（驼峰拆词、小写、连字符）。
- 常量：`GL_ARRAY_BUFFER` → `gl-array-buffer`（去 `GL_`、小写、下划线→连字符）。
  常量全量表在 `constants.rkt`，由 `generate-constants.rkt` 生成。
- 类型后缀（`1f`/`3f`/`iv`/`fv`）算一个词：`gl-uniform-matrix-4fv`。
- 冲突例外：`GL_CULL_FACE` → `var-cull-face`（避开函数 `gl-cull-face`）。

`(provide (all-defined-out))`；raw 名**原样保留**供高级用法。

另有 `core/opengl/alias.rkt`：给“名字不准确”的函数加语义别名，例如
`gl-clear-color` → `gl-set-clear-color`、`gl-clear` → `gl-clear-buffers`。
它只加别名、不改行为，是后续补充命名的唯一入口。细节见
[`core/opengl/README.md`](core/opengl/README.md)。

---

## 3. Part 3.5 · `core/easy/` —— 便利层

把 1:1 的 `gl-*` 包成「返回/接收单个句柄、直接吃 ffi 向量」的便利函数。
命名**不用 `gl-*`**（`glGenBuffer` 这个 C 符号并不存在），走工具层 `<资源>-<动词>`。

| 逻辑 | 文件 | 名字 |
|---|---|---|
| GL 对象句柄（分配 / 删除） | `object.rkt` | 单句柄 `buffer-new` / `texture-new` / `vertex-array-new` / `framebuffer-new` / `renderbuffer-new`、`*-delete`；多句柄 `buffers-new` / `textures-new` / `vertex-arrays-new` / `framebuffers-new` / `renderbuffers-new`、`*-delete`；多值版 `*-new/values` |
| 缓冲上传 | `buffer.rkt` | `buffer-upload` `buffer-update` |
| uniform 上传 | `uniform.rkt` | `uniform-set!`（按 GLSL 类型符号分派） |

细节见 [`core/easy/README.md`](core/easy/README.md)。

### 3.1 生命周期与 Racket GC（关键约定）

**句柄 = 裸 `GLuint` + 手动生命周期，不挂终结器、不自动回收。** 理由：

- GL 删除必须在**拥有该对象的上下文所在线程**执行；Racket 终结器在 GC 线程/不确定时机运行，
  轻则 `GL_INVALID_OPERATION`，重则崩溃。
- 对象间有依赖（program ↔ shader）；终结器顺序不保证。
- 跨上下文共享的对象无法安全自动删。
- 本库范围本就排除 GL 对象管理。

> 若将来做自动回收，正确机制是：终结器只把 handle **入队**，GL 线程帧循环排空（按上下文分桶）。

**数据路径**：只用同步拷贝型 GL 调用（`glBufferData` / `glShaderSource` / `glTexImage2D`）。
外部 `opengl` 绑定的 `_pointer/intptr` 负责「Racket 向量 → 调用期 C 指针」，
调用返回后 Racket 向量可被 GC 移动/回收。**不变量**：绝不引入「GL 长期持有 Racket 侧指针」
的调用（如 `glMapBuffer` 式常驻指针）——由 `access-api-test.rkt` 的 grep 约束守着。

**所有权**：`*-new` 的句柄归调用方，用完自行 `*-delete`；`buffer-upload` / `uniform-set!` 无所有权转移。

---

## 3.5 Part 4 · `core/meta/` —— 表驱动的编译期代码生成

消费纯包产出的**编译期表**（`<name>-interface` / `<Name>-fields`），在展开期生成 `gl-*` 调用字面量。

| 逻辑 | 文件 | 名字 |
|---|---|---|
| 顶点布局 | `core/meta/vertex-layout.rkt` | `glsl-vertex-layout!` |
| uniform setter | `core/meta/uniform-setter.rkt` | `glsl-uniform-setter!`（Racket setter 名用表面名，GL 查询用 GLSL 名） |

```racket
(glsl-struct vertex (vec3 pos) (vec3 normal) (vec2 uv))
(glsl-shader vert (version 330 core)
             (layout (location 0) in vec3 pos) …)   ; 属性名 = struct 字段名
(glsl-vertex-layout! vert vertex)
;; 展开： (gl-vertex-attrib-pointer 0 3 gl-float #f 32 0) (gl-enable-vertex-attrib-array 0) …
```

- 表来源：纯包的 `glsl-shader`（接口表）/ `glsl-struct`（字段表）。
- **按名字自动对齐**：字段名 = shader `in` 名（按归一后的 GLSL 标识符比较，
  `model-pos` ↔ `model_pos` 可对上）；顺序可不同。
- **编译期校验**：字段缺 in / in 缺字段 / 类型不符 → 展开期报错。
- 依赖：编译期读纯包（`interface`/`type`）+ 运行期 emit `gl-*`（故只在 `#lang glsl-opengl` 用）。
  见 [`core/meta/README.md`](core/meta/README.md)。

## 4. 胶水 · `core/tool/` —— 唯一组合点

把 Part 1 产出的 GLSL 文本 + Part 3 的 `gl-*` 接起来。

| 文件 | 提供名 |
|---|---|
| `compile.rkt` | `shader-compile`（旧名 `compile-shader`） |
| `program.rkt` | `program-link` `program-use` `shader-delete` `program-delete` `build-program`（宏） `build-program/list` `uniform-location`；旧名 `link-program` `use-program` `delete-shader` `delete-program` |

工具层刻意不与 raw 层同基名（`shader-compile` ↔ `gl-compile-shader`、`program-link` ↔ `gl-link-program`）。

**三元报错**：`shader-compile` / `program-link` 失败时，`shader/error` 渲染
「GL 原始日志 → 美化 GLSL + 报错行 → `.rkt` 源文件行」三段式。

注意：`tool/program.rkt`（GL program 生命周期）与 `glsl/program.rkt`（`glsl-program` 源码产物）
**同名不同物**。细节见 [`core/tool/README.md`](core/tool/README.md)。

---

## 5. 命名归属（本包相关部分）

| 名字形态 | 归属 | 例子 |
|---|---|---|
| `gl-<opengl符号>` | OpenGL C API 的 **1:1 机械映射**（不发明、不加逻辑） | `gl-create-shader`、`gl-array-buffer` |
| `<资源>-<动词>` | 本包的便利/胶水层（非 `gl-`） | `buffer-new`、`buffer-upload`、`uniform-set!`、`shader-compile`、`program-link` |

规则：只差 `gl-` 的对照（`compile-shader` vs `gl-compile-shader`）要避免，
用第二个词区分动作（`shader-compile`）；`gl-*` 绝不用于自己造的东西。
纯包部分的命名（`glsl-*`、`v*`、`vec-array*`…）见[纯包 DESIGN](../racket-shader/DESIGN.md)。

---

## 6. 着色器编译与静态缓存判定

> 本节记录「除了运行时动态编译 GLSL，能否离线编译好再加载」的**判定信息**，
> 供将来决策。当前结论：**暂不做**，原因见末尾。

OpenGL 里有两种「静态」，性质完全不同。

### 6.1 机制 A：Program binary（驱动内编译产物的缓存）

```racket
;; 链接前声明"这个 program 的二进制可取出"
(gl-program-parameter-i prog GL_PROGRAM_BINARY_RETRIEVABLE_HINT 1)
;; attach + link …
;; 取出（格式 + 字节）：
(gl-get-program-binary prog buf-size length-out format-out ptr)
;; 下次直接加载，跳过 shader 编译 + 链接：
(gl-program-binary prog format ptr len)
```

`opengl` 包**已有**：`glProgramParameteri`、`glGetProgramBinary`、`glProgramBinary`、
常量 `GL_PROGRAM_BINARY_LENGTH` / `..._FORMATS` / `..._RETRIEVABLE_HINT`。

**限制（关键）**：
- 二进制格式由**驱动/GPU 私有定义**（opaque），同一机器同一驱动版本才靠得住；
  换厂商/驱动/驱动升级 → `glProgramBinary` 报 `GL_INVALID_OPERATION`，**必须回退到源码编译**。
- 因此它是**本地缓存**，不是可分发产物，不能打进安装包。
- 二进制里**没有** Racket 侧接口信息（`glsl-interface`：uniform 名字/类型/location）。
  想要反射，得另外保存源 shader 的 interface。

### 6.2 机制 B：SPIR-V（离线前端编译）

```
# 离线（外部工具链 glslang）
glslangValidator --target-env opengl4.6 -G vert.glsl -o vert.spv
```
```racket
;; 运行时
(gl-shader-binary 1 (u32vector shader) GL_SHADER_BINARY_FORMAT_SPIR_V ptr len)
(gl-specialize-shader shader "main" 0 #f #f)   ; ← 本包缺这个绑定
;; 再 attach + link
```

**限制（关键）**：
- 需 GL 4.6 / `ARB_gl_spirv`。
- 是 **OpenGL 版 SPIR-V**（target-env 与 Vulkan 不同），不能混用。
- 必须写**显式** `layout(location=…)` / `binding=…`（SPIR-V 不给自动分配）。
- 驱动仍要把 SPIR-V 编成 GPU ISA —— 省前端解析，不是「零运行时编译」。
- **当前 `opengl` 包未收录 `glSpecializeShader`，也没有 `GL_SHADER_BINARY_FORMAT_SPIR_V`
  常量**（`glShaderBinary` 本身有）。这条路要么给 `opengl` 包补绑定，要么自己用
  `get-ffi-obj` 动态取地址。

### 6.3 对比

| | GLSL 源码（现状） | Program binary | SPIR-V |
|---|---|---|---|
| 编译时机 | 运行时 | 首次运行时（驱动）→ 之后加载 | 构建期（glslang） |
| 可移植性 | 高（文本） | **无**（驱动私有） | 中（标准 IR，分 GL/Vulkan target） |
| 运行时还编译吗 | 全量 | 缓存命中则不 | 驱动后端仍编 ISA |
| `opengl` 包绑定 | ✓ | ✓ | ✗ 缺 `glSpecializeShader` + 常量 |
| 需外部工具 | 无 | 无 | glslangValidator |
| 是否附接口反射 | 有（`glsl-interface`） | 无 | 无 |

### 6.4 现结论与将来落点

**结论：暂不做**（`README.md` 范围已把 program binary 列为不做）。它属于「GL 资源/性能」，
不属于本包「写 GLSL / 造值 / 讲清报错」的定位。

将来若做：
- **启动缓存**（同一机器反复跑）→ 放 `core/easy/`：`program-binary-save` / `program-binary-load`，
  或给 `build-program` 一个可选 cache。需处理「驱动指纹 + 失效回退 + 另存 interface」。
  代价中等，`opengl` 绑定已齐。
- **SPIR-V 离线** → 更大：要给 `opengl` 补 `glSpecializeShader`，加「把 `(glsl ...)` 的 `src`
  导出成 `.glsl` → 调 glslang → 加载 `.spv`」的构建步骤。会引入「库依赖外部编译器」这条新边界，
  与当前「纯 Racket + opengl」的定位冲突，通常应改用 Vulkan。

---

## 7. 测试

需显示器 + GL：`lang-opengl-test` / `control-flow-gl-test` / `int-attrib-test` / `double-test`。
无需显示器（名字 + 可执行约束）：`access-api-test`（含 GC 不变量 + 依赖边界）、`uniform-test`。

```bash
racket racket-shader-opengl/core-test/access-api-test.rkt
racket racket-shader-opengl/core-test/uniform-test.rkt
```
