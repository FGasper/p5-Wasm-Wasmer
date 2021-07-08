import "wasi";

import { JSONEncoder } from "assemblyscript-json";

@external("cpanel", "slurp_text")
export declare function slurp_text (path: string): string;

type myJsonType = ArrayBuffer;

const _OPEN_BRACE : u8 = '{'.charCodeAt(0) as u8;
const _CLOSE_BRACE : u8 = '}'.charCodeAt(0) as u8;

function _exportJSONObject (encoder: JSONEncoder) :myJsonType {

    // lacks surrounding {}
    let rawJson :Uint8Array = encoder.serialize();

    let json = new Uint8Array(2 + rawJson.length);

    json.set(rawJson, 1);
    json[0] = _OPEN_BRACE;
    json[json.length - 1] = _CLOSE_BRACE;

    return json.buffer;
}

function _stringDict2Json(cpuser: Map<string,string>): myJsonType {
    let encoder = new JSONEncoder();

    let keys: string[] = cpuser.keys();

    for (let i=0; i<keys.length; i++) {
        let name: string = keys[i];
        encoder.setString(name, cpuser.get(name));
    }

    return _exportJSONObject(encoder);
}

function _populateCpuser(cpuser: Map<string,string>): void {
    let text = slurp_text("/var/cpanel/users/superman");

    let lines :string[] = text.split("\n");
    let line :string;

    let hashAt :i32;
    let equalAt :i32;

    for (let l=0; l<lines.length; l++) {
        line = lines[l];

        equalAt = line.indexOf("=");
        if (-1 === equalAt) continue;

        hashAt = line.indexOf("#");
        if (-1 !== hashAt) {
            line = line.substring(0, hashAt);
        }

        cpuser.set( line.substring(0, equalAt), line.substring(1 + equalAt) );
    }
/*
    text += "\n" if !text.endsWith("\n");

    let u :u32 = 0;
    let lineEnd :i32;
    let key: string, value: string;

    let nextEqualIdx :i32 = text.indexOf("=");

    while (u < text.length) {
        lineEnd = text.indexOf("\n", u);

        if (lineEnd > nextEqualIdx) {
            key = text.substring(

            nextEqualIdx = text.indexOf("=", u);
        }

        u = 1 + lineEnd;
    }
*/
}

export function load_cpuser_file_JSON (): myJsonType {
    let cpuser = new Map<string,string>();

    _populateCpuser(cpuser);

    return _stringDict2Json(cpuser);
}
