var fs = require("fs");

var loader = require("@assemblyscript/loader");

loader.instantiate(
  // Binary to instantiate
  fs.readFileSync("validate_ipv4.wasm"), // or fs.readFileSync
                           // or fs.promises.readFile
                           // or just a buffer
  // Additional imports
  {}
).then(({ exports }) => {
    const { __newString, __getString } = exports;

    function doValidate(aStr, bStr) {
        let aPtr = __newString(aStr)
        let cPtr = exports.validate_ipv4(aPtr)
        let cStr = __getString(cPtr)
        return JSON.parse(cStr);
    }

    console.log(doValidate("1.2.3.04"));
})
