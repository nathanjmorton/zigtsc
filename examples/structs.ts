interface Point {
    x: number;
    y: number;
}

function distance(a: Point, b: Point): number {
    let dx: number = b.x - a.x;
    let dy: number = b.y - a.y;
    return dx * dx + dy * dy;
}

const p1: Point = { x: 0, y: 0 };
const p2: Point = { x: 3, y: 4 };
const dist: number = distance(p1, p2);
console.log(dist);
