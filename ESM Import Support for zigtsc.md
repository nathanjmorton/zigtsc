# ESM Import Support for zigtsc
## Problem
zigtsc currently only processes a single `.ts` file. We want to support ESM-style `import { ClassName } from './module'` so that:
* The `init` command scaffolds a multi-file project (main.ts + counter.ts)
* The transpile pipeline resolves imports, parses imported files, and merges their declarations
* The C/C++ output links correctly (classes from imports appear in the unified .h/.cpp/.c output)
## Current State
* Lexer has no `import` or `from` keywords
* Parser only handles single-file top-level: function, class, interface, type, let/const
* `runTranspile` in `src/main.zig` reads one file, parses, checks, and codegens
* Codegen (codegen_cpp.zig `generateUnified`) produces `<base>.h`, `<base>.cpp`, `<base>.c` from a single AST
## Proposed Changes
### 1. Lexer: Add `import` and `from` keywords
`src/token.zig`: Add `kw_import` and `kw_from` to `Tag` enum, `isKeyword`, and `keywords` map.
### 2. AST: Add `import_decl` node
`src/ast.zig`: Add `import_decl` to `Node.Tag`. Data layout: `lhs` = packed StringRef for the module path, `rhs` = extra_start for the list of imported names. Extra: `[count, name_string_ref_0, name_string_ref_1, ...]`.
### 3. Parser: Parse import declarations
`src/parser.zig`: In `parseTopLevel`, handle `kw_import`. Parse the form:
```warp-runnable-command
import { Name1, Name2 } from './path';
```
Store the module path (string literal without quotes) and imported names in the AST.
### 4. Multi-file resolution in transpile
`src/main.zig` `runTranspile`:
* After parsing the main file, walk the program's top-level nodes looking for `import_decl`
* For each import, resolve the path relative to the input file's directory (append `.ts` if needed)
* Read and parse each imported file
* Build a merged statement list: imported file declarations first, then main file statements (skipping import_decl nodes)
* Reconstruct a single merged program AST node, then run checker + codegen on it
This "flatten + merge" approach reuses the existing single-AST pipeline without architectural changes.
### 5. Checker + Codegen: Skip import_decl
* `src/checker.zig` `checkNode`: add `import_decl => {}` case
* `src/codegen.zig`, `codegen_js.zig`, `codegen_cpp.zig`, `codegen_cuda.zig`: skip `import_decl` in all emission loops (the generate/emitMainFile/emitUnifiedCEntry functions that iterate program statements)
### 6. Update `init` command
In `src/main.zig`:
* Add a `COUNTER_TEMPLATE` constant for `src/counter.ts` containing an exported `Counter` class
* Update `INIT_TEMPLATE` for `src/main.ts` to import Counter from `'./counter'` and use it
* Update `runInit` to write both files
### 7. Tests
In `src/tests.zig`:
* Lexer test: `import` and `from` lex as keywords
* Parser test: `import { Counter } from './counter'` parses without errors
* (E2E multi-file tests are harder in-memory; manual testing via `zigtsc init` + `zigtsc transpile` covers integration)
