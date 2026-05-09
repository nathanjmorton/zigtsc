// CUDA vector addition example
//
// Transpile:  zigtsc transpile examples/vecadd.ts
// Compile:    nvcc examples/zigtscout/vecadd.cu -o vecadd

kernel function vecadd(a: f32[], b: f32[], c: f32[], n: i32): void {
    const idx: i32 = threadIdx.x + blockIdx.x * blockDim.x;
    if (idx < n) {
        c[idx] = a[idx] + b[idx];
    }
}
