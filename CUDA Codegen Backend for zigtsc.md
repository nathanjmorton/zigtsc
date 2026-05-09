# CUDA Codegen Backend for zigtsc
Add a CUDA C++ (`.cu`) codegen backend so that `kernel` functions in TypeScript source emit `__global__` CUDA device functions.
## Current State
zigtsc has 3 codegen backends (`codegen.zig` for C, `codegen_cpp.zig` for C++, `codegen_js.zig` for JS), each an independent struct consuming the shared AST + Checker. The parser already handles member expressions (`threadIdx.x`), array indexing, arithmetic, and control flow — all needed for basic CUDA kernels.
## Proposed Changes
### 1. Token — add `kw_kernel`
`src/token.zig`: Add `kw_kernel` to the `Tag` enum, the `isKeyword` switch, and the `keywords` string map (`"kernel" → .kw_kernel`).
### 2. AST — add `kernel_decl` tag
`src/ast.zig`: Add `kernel_decl` to `Node.Tag`. It uses the same data layout as `func_decl` (name in `lhs`, body in `rhs`, extra = [ret_type, param_count, params...]).
### 3. Parser — handle `kernel function`
`src/parser.zig`: In `parseTopLevel`, when current token is `kw_kernel`, consume it, then parse a function declaration as usual but emit a `kernel_decl` node instead of `func_decl`.
### 4. Checker — accept `kernel_decl`
`src/checker.zig`: In `checkNode`, handle `.kernel_decl` the same as `.func_decl` (call `checkFuncDecl`).
### 5. New file: `src/codegen_cuda.zig`
A new codegen struct `CodeGenCuda` following the same pattern as `CodeGen`/`CodeGenCpp`. Key behaviors:
* Emits `#include <cuda_runtime.h>` and standard C headers
* `kernel_decl` nodes → `__global__` function prefix
* `func_decl` nodes → `__host__` (or plain) functions
* CUDA builtins (`threadIdx`, `blockIdx`, `blockDim`, `gridDim`) recognized in `emitExpr` and passed through as-is (they're valid CUDA C++ identifiers)
* Type mapping: `f32[]` → `float*`, `i32` → `int32_t`, etc. (same as C codegen)
* `console.log` → `printf` (same as C codegen)
* Top-level statements → `main()` body
* Output is a single `.cu` file
### 6. Main — add `--cuda` flag
`src/main.zig`: In `runTranspile`, after generating JS and C/C++ output, also run `CodeGenCuda` and write a `.cu` file to the `zigtscout/` directory.
### 7. Example + test
* Add `examples/vecadd.ts` with a kernel function using `threadIdx.x`, `blockIdx.x`, `blockDim.x`
* Add an e2e test in `tests.zig` that parses a kernel function and verifies the CUDA output contains `__global__`
## Target TypeScript Syntax
```warp-runnable-command
kernel function vecadd(a: f32[], b: f32[], c: f32[], n: i32): void {
    const idx: i32 = threadIdx.x + blockIdx.x * blockDim.x;
    if (idx < n) {
        c[idx] = a[idx] + b[idx];
    }
}
```
## Generated CUDA Output
```warp-runnable-command
#include <cuda_runtime.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
__global__ void vecadd(float* a, float* b, float* c, int32_t n) {
    int32_t idx = (threadIdx.x + (blockIdx.x * blockDim.x));
    if ((idx < n)) {
        c[idx] = (a[idx] + b[idx]);
    }
}
```
