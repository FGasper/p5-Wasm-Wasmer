declare function sayhi(): void;

declare function count(start: i32, end: i32): i32;

export function call_sayhi(): void {
    sayhi();
}

export function call_count(start: i32, end: i32): i32 {
    return count(start, end);
}
