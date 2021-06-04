import { JSONEncoder } from "assemblyscript-json";
import { RegExp } from "assemblyscript-regex";

export function validate_ipv4(str: string): string {
    var thearray = _validate_ipv4(str);

    let encoder = new JSONEncoder();

    if (thearray.length > 0) {
        encoder.setString("type", thearray[0]);
    }
    else {
        encoder.setNull("type");
    }

    if (thearray.length > 1) {
        encoder.setString("detail", thearray[1]);
    }
    else {
        encoder.setNull("detail");
    }

    return '{' + encoder.toString() + '}';
}

var POSITIVE_INTEGER = new RegExp('^\\d+$');
var LEADING_ZEROES = new RegExp('^0+[0-9]+$');

function _validate_ipv4(str: string ): string[] {
    var chunks = str.split(".");

    if (chunks.length !== 4 || chunks[0] === "0") {
        return ["wrongOctetCount"];
    }

    for (var i = 0; i < chunks.length; i++) {
        if (!POSITIVE_INTEGER.test(chunks[i])) {
            return ["notPositiveInteger", i.toString()];
        }

        var chunknum = parseInt(chunks[i], 10);

        if (chunknum > 255) {
            return ["excessOctet", i.toString()];
        }

        // We need to account for leading zeroes, since those cause issues with BIND
        // Check for leading zeroes and error out if the value is not just a zero
        if (LEADING_ZEROES.test(chunks[i])) {
            return ["leadingZeroes", i.toString()];
        }
    }

    return [];
}
