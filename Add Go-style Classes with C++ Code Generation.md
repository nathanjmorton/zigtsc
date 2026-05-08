# Add Go-style Classes + Dual C++/JS Code Generation
## Problem
zigtsc currently compiles TypeScript → single C file. Goals:
1. Add class support (Go-style: no inheritance, composition via interfaces)
2. Add JS transpilation target (strip types, emit valid JS)
3. Restructure C codegen → C++ with separate `.h`/`.cpp` per class
## Current State
* 7 source files: `token.zig`, `lexer.zig`, `ast.zig`, `parser.zig`, `checker.zig`, `codegen.zig`, `main.zig`
* Parser/checker handle functions, interfaces (→ C structs), variables, control flow
* Single C output via `codegen.zig` (~220 lines)
* 13 passing tests in `tests.zig`
* CLI: `zigtsc <input.ts> [output.c]`
## Proposed Approach
### Phase 1: AST & Parser — class support
Add to `token.zig`: `kw_class`, `kw_new`, `kw_this` keywords
Add to `ast.zig`: `class_decl`, `method_decl`, `constructor_decl`, `new_expr`, `this_expr` node tags
Add to `parser.zig`:
* `parseClassDecl()` — parses `class Name { field: Type; constructor(...) { } method(...): RetType { } }`
* Store in extra data: field count, field nodes, constructor node, method count, method nodes
* `parseNewExpr()` — `new ClassName(args)`
* `this` as a primary expression
* Integrate `kw_class` into `parseTopLevel()`, `kw_new`/`kw_this` into `parsePrimary()`
### Phase 2: Type Checker — class support
Add to `checker.zig`:
* `ClassDef` struct: `{ name, fields: []FieldDef, methods: []MethodSig, constructor_params: []ParamSig }`
* `classes: ArrayList(ClassDef)` alongside existing `structs`
* `current_class: ?usize` — index into classes, set during method checking
* `checkClassDecl()` — register class, check constructor body, check each method body
* `this` binding — when `current_class` is set, inject `this` as `class_t` type into method scope
* Resolve `this.field` via member_expr on class_t type
* `new ClassName(args)` — resolve to class_t, validate constructor args
* Add `class_t` to Type enum
### Phase 3: JS Codegen (new file `codegen_js.zig`)
Simpler than C codegen — mostly strip types from the original TS:
* Functions → strip param types and return type annotations
* Variables → strip type annotations (`let x: number = 5` → `let x = 5`)
* Interfaces → omit entirely (compile-time only)
* Classes → emit JS class syntax directly (trivial mapping)
* `console.log` → stays as-is
* Expressions → nearly 1:1 (already JS-compatible syntax)
* `new ClassName(args)` → stays as-is
* Output: single `.js` file
### Phase 4: C++ Codegen (restructure `codegen.zig` → `codegen_cpp.zig`)
Rename existing `codegen.zig` → `codegen_cpp.zig`, restructure for multi-file output:
* Return type changes from single `[]const u8` to `ArrayList(OutputFile)` where `OutputFile = { name, content }`
* For each class: emit `Name.h` (pragma once, class decl with fields + method sigs) + `Name.cpp` (includes, method impls)
* For top-level code + free functions: emit `main.cpp`
* Dependency analysis: scan class fields/method params for other class types → emit `#include`s
* `this.field` → `this->field` in method bodies
* `new ClassName(args)` → `new ClassName(args)` (same syntax in C++)
* Interfaces → still emit as C++ structs
### Phase 5: CLI + Build Integration
Modify `main.zig`:
* Add `-target` flag: `c` (default, legacy single-file), `cpp`, `js`
* For `cpp` target: second arg is output directory, write all `.h`/`.cpp`/`main.cpp` files
* For `js` target: second arg is output `.js` file
* For `c` target: existing behavior unchanged
## Key Design Decisions
1. **No inheritance** → no vtables, no virtual dispatch, no override checks
2. **Go-style** → interfaces are contracts, classes implement via having matching fields
3. **`this` only in methods** → checker enforces this
4. **JS codegen first** → validates parser/checker design, fast to implement
5. **C++ multi-file** → each class gets `.h`/`.cpp` pair, free functions + main in `main.cpp`
6. **Backward compatible** → `-target c` preserves existing single-file C output
## Implementation Order
1. Token/AST: add class, new, this keywords and node tags
2. Parser: class decl, constructor, methods, new expr, this expr
3. Checker: ClassDef, class_t type, this binding, new expr validation
4. JS codegen: new file `codegen_js.zig`
5. C++ codegen: restructure `codegen.zig` → `codegen_cpp.zig` with multi-file output
6. CLI: `-target` flag, directory output for cpp
7. Tests for all new features
## Out of Scope
* Inheritance / extends
* Static fields/methods
* Getters/setters
* Generics
* Operator overloading
* Destructors/RAII
* Access modifiers (everything is public)
