
var fs = require("fs");

var loader = require("@assemblyscript/loader");

loader.instantiate(
  // Binary to instantiate
  fs.readFileSync("concat.wasm"), // or fs.readFileSync
                           // or fs.promises.readFile
                           // or just a buffer
  // Additional imports
  {}
).then(({ exports }) => {
    const { concat } = exports;
    const { __newString, __getString } = exports;

    function doConcat(aStr, bStr) {
        let aPtr = __newString(aStr)
        let bPtr = __newString(bStr)
        let cPtr = concat(aPtr, bPtr)
        let cStr = __getString(cPtr)
        return cStr
    }

    console.log(doConcat("Hello ", "world!"));
})
