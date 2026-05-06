// ── zigtsc starter project ──────────────────────────────────────────────
//
// This file demonstrates the full zigtsc TypeScript subset.
// Transpile it to any of three targets:
//
//   zigtsc main.ts                         # C output to stdout
//   zigtsc main.ts output.c                # C output to file
//   zigtsc main.ts -target js output.js    # JavaScript output
//   zigtsc main.ts -target cpp out/        # C++ multi-file output
//
// Then compile/run with zigc (https://zigc.nathanjmorton.com):
//   zigc init myapp && cp output.c myapp/src/main.c && cd myapp && zigc run     # C
//   node output.js                                                               # JavaScript
//   zigc init myapp --cpp && cp out/*.h out/*.cpp myapp/src/ && cd myapp && zigc run  # C++

// ── Interfaces ──────────────────────────────────────────────────────────
// Interfaces compile to C structs, are omitted in JS output,
// and become C++ structs in the cpp target.

interface Point {
    x: number;
    y: number;
}

// ── Functions ───────────────────────────────────────────────────────────
// Free functions work across all targets.

function distance(a: Point, b: Point): number {
    let dx: number = b.x - a.x;
    let dy: number = b.y - a.y;
    return dx * dx + dy * dy;
}

// ── Classes ─────────────────────────────────────────────────────────────
// Go-style classes: no inheritance, no static methods.
// In C++ target, each class gets its own .h/.cpp pair.
// In JS target, classes emit directly as ES6 classes.
// In C target, classes are not yet supported (use interfaces instead).

class Counter {
    value: i32;

    constructor(init: i32) {
        this.value = init;
    }

    increment(): void {
        this.value = this.value + 1;
    }

    decrement(): void {
        this.value = this.value - 1;
    }

    getVal(): i32 {
        return this.value;
    }
}

// ── Top-level code ──────────────────────────────────────────────────────
// Top-level statements become main() in C/C++ output,
// and stay at module scope in JS output.

const p1: Point = { x: 0, y: 0 };
const p2: Point = { x: 3, y: 4 };
console.log(distance(p1, p2));

const c = new Counter(10);
c.increment();
c.increment();
c.decrement();
console.log(c.getVal());
