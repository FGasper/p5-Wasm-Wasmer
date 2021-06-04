var fs = require("fs");
const { WASI } = require("wasi");
const wasi = new WASI();

var loader = require("@assemblyscript/loader");

loader.instantiate(
  // Binary to instantiate
  fs.readFileSync("wasi.wasm"), // or fs.readFileSync
                           // or fs.promises.readFile
                           // or just a buffer
  // Additional imports
  { wasi_snapshot_preview1: wasi.wasiImport }
).then((stuff) => {
console.log(stuff);
    const { exports } = stuff;
    const { greet, say } = exports;
    const { __newString, __getString } = exports;

console.log(exports);

    wasi.start(stuff.instance);

    greet();

    function doSay(aStr, bStr) {
        let aPtr = __newString(aStr)
        let cPtr = say(aPtr)
        let cStr = __getString(cPtr)
        return cStr
    }

    console.log(doSay("heyheyhey"));
})
