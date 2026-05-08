class Counter {
    value: i32;
    step: i32;

    constructor(init: i32, step: i32) {
        this.value = init;
        this.step = step;
    }

    increment(): void {
        this.value = this.value + this.step;
    }

    getVal(): i32 {
        return this.value;
    }
}

const c = new Counter(0, 5);
c.increment();
c.increment();
c.increment();
console.log(c.getVal());
