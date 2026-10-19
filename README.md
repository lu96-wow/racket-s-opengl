# racket-shader-opengl —— GLSL + OpenGL

**中文** | [English](README.en.md)

`#lang glsl-opengl`（collection `glsl-opengl`）：在纯 GLSL 包 [`racket-shader`](https://github.com/lu96-wow/s-shader/blob/racket-shader/README.md)
之上叠加 OpenGL 层。**单向依赖** `racket-shader`（反向不成立）。

定位：把「用 `racket-shader` 写出的 GLSL」和「`opengl` 包的 C API」接起来，并提供一层
消样板的对象/缓冲/uniform 便利函数。GL 的对象管理/状态/窗口仍由调用方负责。

设计与逻辑分层见 [DESIGN.md](DESIGN.md)。

## 安装

### 0. 前置条件

- Racket ≥ 8.x（开发用的是 v9.3）
- 支持 GL 3.3 / 4.0 core profile 的显卡驱动——只在跑 GL 代码/测试时需要，纯 `#lang glsl` 侧不需要
- OpenGL 头文件/库由 `opengl` 包在安装时自带的 FFI 绑定处理，无需手工装开发包

### 1. 先装依赖包 `racket-shader`（必须）

本包**单向依赖** [`racket-shader`](https://github.com/lu96-wow/s-shader)
（提供集合 `shader` / `glsl` / `slang`）。该包不在 pkgs.racket-lang.org 上，
而 `raco pkg install` 只按**包名**解析依赖，所以必须先把它装好，否则装本包会报
`racket-shader` 找不到。

**A. 从 GitHub 直接装**（推荐；必须用 `--name`，因为仓库名 `s-shader` ≠ 包名 `racket-shader`）

```bash
git clone -b racket-shader https://github.com/lu96-wow/s-shader.git racket-shader
raco pkg install --auto --link ./racket-shader        # 本地链接，改代码即时生效

# 或者不落地直接装（指定分支 + 包名）
# raco pkg install --auto --name racket-shader \
#   "https://github.com/lu96-wow/s-shader.git#racket-shader"
```

**B. 已有本地副本**

```bash
raco pkg install --auto --link /path/to/racket-shader
```

验证依赖已就位：

```bash
racket -e '(require glsl slang) (displayln "racket-shader ok")'
```

### 2. 装本包

```bash
git clone https://github.com/lu96-wow/racket-s-opengl.git
raco pkg install --auto --link ./racket-s-opengl
```

`--auto` 会自动从 catalog 拉取 `opengl` 及测试用的 `gui-lib` / `rackunit-lib`；
`racket-shader` 已在第 1 步装好，不会重复下载。

如果两个仓库是**同级目录**，也可以一条命令一起装（`racket-shader` 必须排在前面）：

```bash
raco pkg install --auto --link ./racket-shader ./racket-shader-opengl
```

### 3. 验证

```bash
racket -e '(require glsl-opengl) (displayln "glsl-opengl ok")'
raco pkg show -u | grep -E "racket-shader|opengl"
```

### 卸载

```bash
raco pkg remove racket-shader-opengl
raco pkg remove racket-shader        # 确认没有其它包还在依赖它
```

依赖 `base`、`racket-shader`、`opengl`（测试另需 `gui-lib`、`rackunit-lib`）。入口：

- **`#lang glsl-opengl`** —— `(require glsl)` + OpenGL 层，`glsl` / `vec3` / `gl-*` / `build-program`
  / `buffer-new` 全部开箱可用。
- **`(require glsl-opengl)`** —— 等价。
- 只要 GLSL 不碰 OpenGL 时用 `#lang glsl`（不拉进 opengl）。

## 快速开始

```racket
#lang glsl-opengl

(define vert
  (glsl (version 330 core)
        (layout (location 0) in vec3 aPos)
        (uniform mat4 uMVP)
        (define (main) void
          (set! gl_Position (* uMVP (vec4 aPos 1.0))))))

(define frag
  (glsl (version 330 core)
        (out vec4 FragColor)
        (define (main) void
          (set! FragColor (vec4 1.0 0.5 0.2 1.0)))))

(define prog (build-program (gl-vertex-shader vert) (gl-fragment-shader frag)))
(program-use prog)

;; 便利层：句柄 / 上传 / uniform（不用裸 (u32vector-ref (gl-gen-buffers 1) 0)）
(define vbo (buffer-new))
(gl-bind-buffer gl-array-buffer vbo)
(buffer-upload gl-array-buffer (vec-array (vec3 -0.5 -0.5 0.0) (vec3 0.5 -0.5 0.0) (vec3 0.0 0.5 0.0))
               gl-static-draw)

(uniform-set! (uniform-location prog "uMVP") 'mat4 (mat4 1.0))
```

## 四层 API

| 层 | 命名 | 例子 | 说明 |
|---|---|---|---|
| Part 3 · raw 映射 | `gl-<C符号>` | `gl-create-shader`、`gl-array-buffer` | `opengl` C API 的 1:1 kebab 映射，**纯机械** |
| Part 3 · 语义别名 | `gl-<更准确的动词>` | `gl-set-clear-color`、`gl-clear-buffers` | 只加别名，不改行为；入口 `core/opengl/alias.rkt` |
| Part 3.5 · 便利层 | `<资源>-<动词>` | `buffer-new`、`buffer-upload`、`uniform-set!` | 组合 raw `gl-*` + 值层，消样板 |
| Part 4 · 表驱动代码生成 | `glsl-*`（读编译期表） | `glsl-vertex-layout!`、`glsl-uniform-setter!` | 展开期读 shader 接口表 + struct 字段表生成 `gl-*` 字面量 |
| 胶水 | `<资源>-<动词>` | `shader-compile`、`program-link`、`build-program` | 把 GLSL 文本编译/链接成 GL 对象 |

## 编译 / 链接 / 报错

```racket
(compile-shader (gl-vertex-shader vert))     ; 或直接用 build-program
(build-program (gl-vertex-shader vert) (gl-fragment-shader frag))   ; 宏
(build-program/list (list (list gl-vertex-shader vert) …))          ; 函数版
(program-use prog)
(uniform-location prog "uMVP")               ; 找不到返回 -1（OpenGL 约定）
```

`shader-compile` / `program-link` 失败时抛异常，消息是**三段式**（GL 原始日志 →
美化后的 GLSL + 报错行 → 对应的 `.rkt` 源文件行）。解析/渲染在纯包 `shader/error`。

所有权：`shader-compile` / `program-link` 失败时释放自己创建的对象；
`build-program/list` 链接成功后 detach + delete 中间 shader；`program-link` 不删除传入的 shader。

## 便利层（`core/easy/`）

### 调用便利（与 GLSL 无关）

| 逻辑 | 名字 |
|---|---|
| GL 对象句柄（分配 / 删除） | 单句柄 `buffer-new` `texture-new` `vertex-array-new` `framebuffer-new` `renderbuffer-new`、`*-delete`；多句柄 `buffers-new` `textures-new` `vertex-arrays-new` `framebuffers-new` `renderbuffers-new`、`*-delete`；多值版 `*-new/values` |
| 缓冲上传 | `buffer-upload` `buffer-update` |
| uniform 上传 | `uniform-set!`（按 GLSL 类型符号分派） |

关键约定：
- 句柄是**裸 `GLuint`**，**不挂终结器、不自动回收**——GL 删除必须在拥有该上下文的线程执行，
  而 Racket 终结器在 GC 线程/不确定时机运行。生命周期由调用方手动管理。
- `buffer-upload` 只读入参、不保留引用；GL 调用是同步拷贝。
- 这一段**不** require `glsl`（语言文本）或 `core/tool`（胶水）——边界由
  `core-test/access-api-test.rkt` 约束。

### 自动对齐宏：已移除，设计待重做

`glsl-vertex-layout!` / `glsl-uniform-setter!`（以及实验性的生成模式）已删除。
它们要把 GLSL 声明、CPU 打包顺序、VAO 的六个数字对上，但只能校验其中一部分：
字段名相等、显式 location、类型匹配可以报错；**打包顺序和「单 VBO」无法校验**。
重做思路（schema 作为枢轴、读/写两个方向的取舍）见 [DESIGN.md](DESIGN.md) §3.5。

在此之前，需要布局和 setter 就**裸写**：

```racket
(gl-vertex-attrib-pointer 0 3 gl-float #f 32 0)
(gl-enable-vertex-attrib-array 0)
;; …
(uniform-set! (uniform-location prog "uMVP") 'mat-4 mvp)
```

## 范围

**做**：GLSL 文本 → shader/program 的编译链接与报错，以及对象/缓冲/uniform 的便利封装。

**不做**（调用方自行封装）：窗口与事件循环；纹理/FBO 的高层封装；UBO/SSBO 绑定、
compute dispatch、program pipeline、**program binary**；图形学数学约定（`look-at`/`perspective`
等）。着色器静态编译（program binary / SPIR-V）的判定见 [DESIGN.md](DESIGN.md) 的
「着色器编译与静态缓存判定」。

## 分层与文件

```
racket-shader-opengl/
  main.rkt                    #lang glsl-opengl（require glsl + 下列各层）
  lang/reader.rkt             #lang 声明
  core/opengl/rename.rkt      Part 3   函数 1:1 映射（gl-*）
  core/opengl/constants.rkt   Part 3   GL_* 常量全量表（生成文件）
  core/opengl/generate-constants.rkt 生成 constants.rkt
  core/opengl/alias.rkt       Part 3   语义别名（如 gl-set-clear-color）
  core/easy/{object,buffer,uniform}.rkt  Part 3.5 调用便利（运行期）
  core/tool/{compile,program}.rkt        胶水：编译 / 链接 / program 生命周期
```

细节见 [DESIGN.md](DESIGN.md)（分层、命名映射、生命周期、表驱动生成、编译/链接胶水）。

## 测试

```bash
# 需显示器 + GL 3.3/4.0
racket racket-shader-opengl/core-test/lang-opengl-test.rkt
racket racket-shader-opengl/core-test/control-flow-gl-test.rkt
racket racket-shader-opengl/core-test/int-attrib-test.rkt
racket racket-shader-opengl/core-test/double-test.rkt
```

无需显示器的测试：`core-test/access-api-test.rkt`、`core-test/uniform-test.rkt`。

## License

MIT
