#lang racket/base

;; ============================================================
;; 块 3 · (glsl) 外 · opengl/rename.rkt —— OpenGL → Racket 命名（kebab-case）
;;
;; opengl 包沿用的是 C 的原始命名，两种风格混在一起：
;;   函数：glGenBuffers、glBufferData、glDrawArrays（驼峰式）
;;   常量：GL_ARRAY_BUFFER、GL_TRIANGLES（全大写 + 下划线）
;;
;; 教程统一改成 Racket 习惯的 kebab-case（全小写 + 连字符）：
;;   函数：glGenBuffers    →  gl-gen-buffers
;;         glDrawArrays    →  gl-draw-arrays
;;   常量：GL_ARRAY_BUFFER →  gl-array-buffer
;;         GL_TRIANGLES    →  gl-triangles
;;
;; 换算规则（三条）：
;;   1. 常量：去掉 GL_ 前缀 → 全小写 → 下划线换成连字符
;;        GL_ARRAY_BUFFER → array-buffer → gl-array-buffer
;;   2. 函数：驼峰拆成单词 → 全小写 → 连字符连接
;;        glGenBuffers → gen buffers → gl-gen-buffers
;;   3. 类型后缀（数字 + 字母，如 1f / 3f / iv / fv）算一个单词
;;        glUniform1f   → gl-uniform-1f
;;        glGetShaderiv → gl-get-shader-iv
;;   例外：函数与常量换算后同名时（如 glCullFace 与 GL_CULL_FACE 都成了 gl-cull-face），
;;        函数保留 gl-*，常量（变量）改加 var- 前缀 → var-cull-face。
;;        与 opengl 自带工具撞名同理：GL_VERSION → var-version、GL_EXTENSIONS → var-extensions。
;;
;; 用法：require 本模块后，代码里只写 kebab-case 的 gl-* 名字；
;;       原始驼峰名不再直接出现在教程代码里。
;;       常量全量表由 constants.rkt 生成；需要新函数时，按上面规则补进本文件。
;; double 精度（dvec/dmat/double）的专属函数也已收录。教程主线用 float，这些先备着。
;; ============================================================

(require opengl
         "constants.rkt")

(provide
 ;; 函数与语义别名
 (all-defined-out)
 ;; 常量全量表（core/opengl/constants.rkt，由 generate-constants.rkt 生成）
 (all-from-out "constants.rkt")
 ;; 唯一例外：gl-vector-sizeof 是 opengl 包自带的工具函数（本就 kebab-case），
 ;; 不是本模块 define 出来的，所以仍要显式转出。
 gl-vector-sizeof)

;; ---------- 函数：驼峰 → kebab-case ----------

(define gl-active-texture             glActiveTexture)
(define gl-attach-shader              glAttachShader)
(define gl-begin                      glBegin)
(define gl-bind-attrib-location       glBindAttribLocation)
(define gl-bind-buffer                glBindBuffer)
(define gl-bind-buffer-base           glBindBufferBase)
(define gl-bind-buffer-range          glBindBufferRange)
(define gl-bind-framebuffer           glBindFramebuffer)
(define gl-bind-renderbuffer          glBindRenderbuffer)
(define gl-bind-texture               glBindTexture)
(define gl-bind-vertex-array          glBindVertexArray)
(define gl-blend-func                 glBlendFunc)
(define gl-blit-framebuffer           glBlitFramebuffer)
(define gl-buffer-data                glBufferData)
(define gl-buffer-sub-data            glBufferSubData)
(define gl-check-framebuffer-status   glCheckFramebufferStatus)
(define gl-clear                      glClear)
(define gl-clear-color                glClearColor)
(define gl-compile-shader             glCompileShader)
(define gl-create-program             glCreateProgram)
(define gl-create-shader              glCreateShader)
(define gl-cull-face                  glCullFace)
(define gl-delete-buffers             glDeleteBuffers)
(define gl-delete-framebuffers        glDeleteFramebuffers)
(define gl-delete-program             glDeleteProgram)
(define gl-delete-renderbuffers       glDeleteRenderbuffers)
(define gl-delete-shader              glDeleteShader)
(define gl-delete-textures            glDeleteTextures)
(define gl-delete-vertex-arrays       glDeleteVertexArrays)
(define gl-depth-func                 glDepthFunc)
(define gl-depth-mask                 glDepthMask)
(define gl-detach-shader              glDetachShader)
(define gl-disable                    glDisable)
(define gl-disable-vertex-attrib-array glDisableVertexAttribArray)
(define gl-draw-arrays                glDrawArrays)
(define gl-draw-arrays-instanced      glDrawArraysInstanced)
(define gl-draw-arrays-instanced-base-instance glDrawArraysInstancedBaseInstance)
(define gl-draw-elements              glDrawElements)
(define gl-draw-elements-base-vertex  glDrawElementsBaseVertex)
(define gl-draw-elements-instanced    glDrawElementsInstanced)
(define gl-draw-range-elements        glDrawRangeElements)
(define gl-enable                     glEnable)
(define gl-enable-vertex-attrib-array glEnableVertexAttribArray)
(define gl-end                        glEnd)
(define gl-framebuffer-renderbuffer   glFramebufferRenderbuffer)
(define gl-framebuffer-texture-2d     glFramebufferTexture2D)
(define gl-front-face                 glFrontFace)
(define gl-gen-buffers                glGenBuffers)
(define gl-gen-framebuffers           glGenFramebuffers)
(define gl-gen-renderbuffers          glGenRenderbuffers)
(define gl-gen-textures               glGenTextures)
(define gl-gen-vertex-arrays          glGenVertexArrays)
(define gl-generate-mipmap            glGenerateMipmap)
(define gl-get-active-uniform-block-iv glGetActiveUniformBlockiv)
(define gl-get-active-uniform         glGetActiveUniform)
(define gl-get-active-uniform-name    glGetActiveUniformName)
(define gl-get-active-uniforms-iv     glGetActiveUniformsiv)
(define gl-get-attrib-location        glGetAttribLocation)
(define gl-get-program-info-log       glGetProgramInfoLog)
(define gl-get-program-iv             glGetProgramiv)
(define gl-get-shader-info-log        glGetShaderInfoLog)
(define gl-get-shader-iv              glGetShaderiv)
(define gl-get-string                 glGetString)
(define gl-get-uniform-block-index    glGetUniformBlockIndex)
(define gl-get-uniform-indices        glGetUniformIndices)
(define gl-get-uniform-location       glGetUniformLocation)
(define gl-line-width                 glLineWidth)
(define gl-link-program               glLinkProgram)
(define gl-map-buffer                 glMapBuffer)
(define gl-map-buffer-range           glMapBufferRange)
(define gl-multi-draw-arrays          glMultiDrawArrays)
(define gl-multi-draw-elements        glMultiDrawElements)
(define gl-pixel-store-i              glPixelStorei)
(define gl-primitive-restart-index    glPrimitiveRestartIndex)
(define gl-read-pixels                glReadPixels)
(define gl-renderbuffer-storage       glRenderbufferStorage)
(define gl-renderbuffer-storage-multisample glRenderbufferStorageMultisample)
(define gl-shader-source              glShaderSource)
(define gl-tex-image-2d               glTexImage2D)
(define gl-tex-parameter-i            glTexParameteri)
(define gl-uniform-block-binding      glUniformBlockBinding)
(define gl-uniform-1f                 glUniform1f)
(define gl-uniform-2f                 glUniform2f)
(define gl-uniform-3f                 glUniform3f)
(define gl-uniform-4f                 glUniform4f)
(define gl-uniform-1i                 glUniform1i)
(define gl-uniform-2i                 glUniform2i)
(define gl-uniform-3i                 glUniform3i)
(define gl-uniform-4i                 glUniform4i)
(define gl-uniform-1ui                glUniform1ui)
(define gl-uniform-2ui                glUniform2ui)
(define gl-uniform-3ui                glUniform3ui)
(define gl-uniform-4ui                glUniform4ui)
(define gl-uniform-1d                 glUniform1d)
(define gl-uniform-2d                 glUniform2d)
(define gl-uniform-3d                 glUniform3d)
(define gl-uniform-4d                 glUniform4d)
(define gl-uniform-matrix-2dv         glUniformMatrix2dv)
(define gl-uniform-matrix-2fv         glUniformMatrix2fv)
(define gl-uniform-matrix-3dv         glUniformMatrix3dv)
(define gl-uniform-matrix-3fv         glUniformMatrix3fv)
(define gl-uniform-matrix-4dv         glUniformMatrix4dv)
(define gl-uniform-matrix-4fv         glUniformMatrix4fv)
(define gl-unmap-buffer               glUnmapBuffer)
(define gl-use-program                glUseProgram)
(define gl-vertex-attrib-divisor      glVertexAttribDivisor)
(define gl-vertex-attrib-pointer      glVertexAttribPointer)
(define gl-vertex-attrib-l-pointer    glVertexAttribLPointer)
(define gl-vertex-attrib-l-1d         glVertexAttribL1d)
(define gl-vertex-attrib-l-2d         glVertexAttribL2d)
(define gl-vertex-attrib-l-3d         glVertexAttribL3d)
(define gl-vertex-attrib-l-4d         glVertexAttribL4d)
;; 整数顶点属性（I = integer，值原样进 shader 的 in ivec*/uvec*）
(define gl-vertex-attrib-ip-pointer   glVertexAttribIPointer)
(define gl-vertex-attrib-i1i          glVertexAttribI1i)
(define gl-vertex-attrib-i1ui         glVertexAttribI1ui)
(define gl-vertex-attrib-i2i          glVertexAttribI2i)
(define gl-vertex-attrib-i2ui         glVertexAttribI2ui)
(define gl-vertex-attrib-i3i          glVertexAttribI3i)
(define gl-vertex-attrib-i3ui         glVertexAttribI3ui)
(define gl-vertex-attrib-i4i          glVertexAttribI4i)
(define gl-vertex-attrib-i4ui         glVertexAttribI4ui)
(define gl-vertex-attrib-i4iv         glVertexAttribI4iv)
(define gl-vertex-attrib-i4uiv        glVertexAttribI4uiv)
(define gl-viewport                   glViewport)

;; gl-vector-sizeof 是 opengl 包自带的 Racket 工具函数，本来就 kebab-case，
;; 不是本模块 define 出来的——所以靠显式 provide 转出（all-defined-out 不含它）。
