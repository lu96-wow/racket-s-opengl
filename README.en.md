# racket-shader-opengl — GLSL + OpenGL

[中文](README.md) | **English**

`#lang glsl-opengl` (collection `glsl-opengl`): an OpenGL layer on top of the pure GLSL package
[`racket-shader`](https://github.com/lu96-wow/s-shader/blob/racket-shader/README.md) (README currently in Chinese).
**One-way dependency** on `racket-shader` (the reverse does not hold).

Scope: bridge "GLSL written with `racket-shader`" and "the C API of the `opengl` package", plus a
thin layer of boilerplate-reducing object/buffer/uniform helpers. GL object management, state, and
windowing remain the caller's responsibility.

See [DESIGN.md](DESIGN.md) for the design and layering.

## Installation

### 0. Prerequisites

- Racket ≥ 8.x (developed against v9.3)
- A GPU driver supporting GL 3.3 / 4.0 core profile — only needed to run GL code/tests; the pure
  `#lang glsl` side does not need it
- OpenGL headers/libraries are handled by the FFI bindings shipped with the `opengl` package; no
  manual dev-package installation is required

### 1. Install the dependency `racket-shader` first (required)

This package has a **one-way dependency** on
[`racket-shader`](https://github.com/lu96-wow/s-shader) (providing the collections `shader` /
`glsl` / `slang`). That package is not on pkgs.racket-lang.org, and `raco pkg install` resolves
dependencies **by package name**, so it must be installed first; otherwise installing this package
fails with "racket-shader not found".

**A. Install straight from GitHub** (recommended; `--name` is mandatory because the repository name
`s-shader` ≠ the package name `racket-shader`)

```bash
git clone -b racket-shader https://github.com/lu96-wow/s-shader.git racket-shader
raco pkg install --auto --link ./racket-shader        # linked in place; edits take effect immediately

# Or install without a local checkout (branch + package name)
# raco pkg install --auto --name racket-shader \
#   "https://github.com/lu96-wow/s-shader.git#racket-shader"
```

**B. You already have a local copy**

```bash
raco pkg install --auto --link /path/to/racket-shader
```

Verify the dependency is in place:

```bash
racket -e '(require glsl slang) (displayln "racket-shader ok")'
```

### 2. Install this package

```bash
git clone https://github.com/lu96-wow/racket-s-opengl.git
raco pkg install --auto --link ./racket-s-opengl
```

`--auto` pulls `opengl` and the test-only `gui-lib` / `rackunit-lib` from the catalog;
`racket-shader` is already installed from step 1 and will not be downloaded again.

If both repositories are **sibling directories**, you can install them with a single command
(`racket-shader` must come first):

```bash
raco pkg install --auto --link ./racket-shader ./racket-shader-opengl
```

### 3. Verify

```bash
racket -e '(require glsl-opengl) (displayln "glsl-opengl ok")'
raco pkg show -u | grep -E "racket-shader|opengl"
```

### Uninstall

```bash
raco pkg remove racket-shader-opengl
raco pkg remove racket-shader        # make sure no other package still depends on it
```

Dependencies: `base`, `racket-shader`, `opengl` (tests additionally need `gui-lib`,
`rackunit-lib`). Entry points:

- **`#lang glsl-opengl`** — `(require glsl)` + the OpenGL layer; `glsl` / `vec3` / `gl-*` /
  `build-program` / `buffer-new` are all available out of the box.
- **`(require glsl-opengl)`** — equivalent.
- Use `#lang glsl` when you only need GLSL and do not touch OpenGL (avoids pulling in `opengl`).

## Quick start

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

;; Convenience layer: handles / upload / uniform (no raw (u32vector-ref (gl-gen-buffers 1) 0))
(define vbo (buffer-new))
(gl-bind-buffer gl-array-buffer vbo)
(buffer-upload gl-array-buffer (vec-array (vec3 -0.5 -0.5 0.0) (vec3 0.5 -0.5 0.0) (vec3 0.0 0.5 0.0))
               gl-static-draw)

(uniform-set! (uniform-location prog "uMVP") 'mat4 (mat4 1.0))
```

## The four API layers

| Layer | Naming | Examples | Notes |
|---|---|---|---|
| Part 3 · raw mapping | `gl-<C symbol>` | `gl-create-shader`, `gl-array-buffer` | 1:1 kebab-case mapping of the `opengl` C API, **purely mechanical** |
| Part 3 · semantic aliases | `gl-<clearer verb>` | `gl-set-clear-color`, `gl-clear-buffers` | Aliases only, behavior unchanged; entry point `core/opengl/alias.rkt` |
| Part 3.5 · convenience layer | `<resource>-<verb>` | `buffer-new`, `buffer-upload`, `uniform-set!` | Composes raw `gl-*` + value layer to remove boilerplate |
| Part 4 · table-driven codegen | `glsl-*` (reads compile-time tables) | `glsl-vertex-layout!`, `glsl-uniform-setter!` | Expansion-time codegen emitting `gl-*` literals from shader interface / struct field tables |
| Glue | `<resource>-<verb>` | `shader-compile`, `program-link`, `build-program` | Compile/link GLSL text into GL objects |

## Compile / link / error reporting

```racket
(compile-shader (gl-vertex-shader vert))     ; or just use build-program
(build-program (gl-vertex-shader vert) (gl-fragment-shader frag))   ; macro
(build-program/list (list (list gl-vertex-shader vert) …))          ; function form
(program-use prog)
(uniform-location prog "uMVP")               ; returns -1 when absent (OpenGL convention)
```

`shader-compile` / `program-link` throw on failure, with a **three-part** message (raw GL log →
pretty-printed GLSL with the offending line → the corresponding `.rkt` source line). Parsing and
rendering live in the pure package's `shader/error`.

Ownership: on failure, `shader-compile` / `program-link` release the objects they created;
`build-program/list` detaches and deletes the intermediate shaders after a successful link;
`program-link` does not delete the shaders passed to it.

## Convenience layer (`core/easy/`)

### Call convenience (no GLSL involved)

| Purpose | Names |
|---|---|
| GL object handles (allocate / delete) | single: `buffer-new` `texture-new` `vertex-array-new` `framebuffer-new` `renderbuffer-new` and `*-delete`; multiple: `buffers-new` `textures-new` `vertex-arrays-new` `framebuffers-new` `renderbuffers-new` and `*-delete`; multiple-values variants `*-new/values` |
| Buffer upload | `buffer-upload` `buffer-update` |
| Uniform upload | `uniform-set!` (dispatches on the GLSL type symbol) |

Key conventions:
- Handles are **bare `GLuint`s** with **no finalizers and no automatic reclamation** — GL deletes
  must run on the thread owning the context, whereas Racket finalizers run on the GC thread at
  unpredictable times. Lifetime is managed manually by the caller.
- `buffer-upload` only reads its arguments and retains no reference; the GL call copies
  synchronously.
- This part does **not** require `glsl` (language text) or `core/tool` (glue) — the boundary is
  enforced by `core-test/access-api-test.rkt`.

### Pairing GLSL with the Racket side (read mode)

Vertex layouts and uniform setters must agree with the shader. The current implementation uses
**read mode**: the GLSL is written first, then a macro reads its compile-time interface table and
aligns the Racket side.

```racket
(shader-struct vertex (vec3 pos) (vec3 normal))
(glsl-shader vert (version 330 core)
             (layout (location 0) in vec3 pos) ...)   ; attribute name = field name
(glsl-vertex-layout! vert vertex)                     ; -> gl-vertex-attrib-pointer ...
(glsl-uniform-setter! prog vert)                      ; -> set-uMVP! ...
```

- Aligned **by name** (`model-pos` <-> `model_pos`), so the order of `in` declarations may differ;
- Compile-time checks: missing `in` / extra `in` / type mismatch all raise errors;
- The numbers (components, GL type, stride, offset) live in `core/easy/attrib.rkt`; `location`
  comes from the GLSL.

> A "generate mode" (schema produces the GLSL declarations plus the bindings) remains a valid
> direction, but its **implementation has been withdrawn and needs a redesign**: what it lacks is
> not macro power but an information source (`shader-struct` says nothing about uniforms) and a
> composition capability (`glsl-splice` takes no arguments, so a schema can only yield a full
> fragment). The layered analysis is in [DESIGN.md](DESIGN.md) §3.5.

## Scope

**Does**: compiling/linking GLSL text into shader/program objects with error reporting, plus
convenience wrappers for objects/buffers/uniforms.

**Does not** (wrap these yourself): windows and event loops; high-level texture/FBO wrappers;
UBO/SSBO binding, compute dispatch, program pipelines, **program binaries**; graphics math
conventions (`look-at` / `perspective`, etc.). For decisions on offline shader compilation
(program binary / SPIR-V), see "着色器编译与静态缓存判定" in [DESIGN.md](DESIGN.md).

## Layering and files

```
racket-shader-opengl/
  main.rkt                    #lang glsl-opengl (requires glsl + the layers below)
  lang/reader.rkt             #lang declaration
  core/opengl/rename.rkt      Part 3   1:1 function mapping (gl-*)
  core/opengl/constants.rkt   Part 3   full GL_* constant table (generated file)
  core/opengl/generate-constants.rkt generates constants.rkt
  core/opengl/alias.rkt       Part 3   semantic aliases (e.g. gl-set-clear-color)
  core/easy/{object,buffer,uniform}.rkt  Part 3.5 call convenience (runtime)
  core/easy/attrib.rkt                   compile-time attribute numbers
  core/easy/read/{vertex-layout,uniform-setter}.rkt   read mode: consume existing GLSL
  core/tool/{compile,program}.rkt        glue: compile / link / program lifecycle
```

See [DESIGN.md](DESIGN.md) for details (layering, naming mappings, lifetimes, table-driven
generation, compile/link glue).

## Tests

```bash
# Requires a display + GL 3.3/4.0
racket racket-shader-opengl/core-test/lang-opengl-test.rkt
racket racket-shader-opengl/core-test/control-flow-gl-test.rkt
racket racket-shader-opengl/core-test/int-attrib-test.rkt
racket racket-shader-opengl/core-test/double-test.rkt
```

Name/constraint tests that need no display: `core-test/access-api-test.rkt`,
`core-test/uniform-test.rkt`.

## License

MIT
