import "wasi";

import { errno } from "bindings/wasi";
import { FileSystem, Descriptor } from "as-wasi";

export function loadFile(path: string): ArrayBuffer {

    console.log("opening " + path);
    let fileOrNull = FileSystem.open(path, "r");
    console.log("opened " + path);
    if (fileOrNull === null) throw new Error("Failed to open the file");

    let file = changetype<Descriptor>(fileOrNull);

    let contentsOrNull = readArrayBuffer(file);
    console.log("did read buffer");
    if (contentsOrNull === null) throw new Error("nonono", errno);

    let contents = changetype<ArrayBuffer>(contentsOrNull);

    return contents;
}

function readArrayBuffer(file: Descriptor): ArrayBuffer | null {
    let s_bytes = file.readAll();
    if (s_bytes === null) {
      return null;
    }

    let u8arr = new Uint8Array(s_bytes.length);

    let i: i32 = 0;
    for (; i < s_bytes.length; i++) u8arr[i] = s_bytes[i];

    return u8arr.buffer;
}
