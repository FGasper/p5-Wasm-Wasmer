import "wasi";

import { errno } from "bindings/wasi";
import { FileSystem, Descriptor } from "as-wasi";

export function loadFile(path: string): string {

    console.log("opening " + path);
    let fileOrNull = FileSystem.open(path, "r");
    console.log("opened " + path);
    if (fileOrNull === null) throw new Error("Failed to open the file");

    let file = changetype<Descriptor>(fileOrNull);

    let contentsOrNull = file.readString();
    console.log("did read string");
    if (contentsOrNull === null) throw new Error("nonono", errno);

    let contents = changetype<string>(contentsOrNull);

    return contents;
}
