import "wasi";

export function greet() :void {
    console.log("Hello from WASI!");
}

export function say(input:string) :void {
    console.log("I say: " + input);
}
