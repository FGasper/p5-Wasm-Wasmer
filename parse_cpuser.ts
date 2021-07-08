import "wasi";

import { JSONEncoder } from "assemblyscript-json";

type myJsonType = ArrayBuffer;
type myCborType = ArrayBuffer;
type binaryString = Uint8Array;
type binaryMap = Map<binaryString, binaryString>;
type binaryKVArray = binaryString[];
type cpuserType = binaryKVArray;

@external("cpanel", "slurp_text")
export declare function slurp_text (path: ArrayBuffer): string;

@external("cpanel", "slurp_binary")
export declare function slurp_binary (path: ArrayBuffer): ArrayBuffer;

const _OPEN_BRACE : u8 = '{'.charCodeAt(0) as u8;
const _CLOSE_BRACE : u8 = '}'.charCodeAt(0) as u8;

const _NEWLINE : u8 = '\n'.charCodeAt(0) as u8;
const _OCTOTHORPE : u8 = '#'.charCodeAt(0) as u8;
const _EQUALS : u8 = '='.charCodeAt(0) as u8;

const _CPUSERDIR : binaryString = Uint8Array.wrap( String.UTF8.encode("/var/cpanel/users/") );
const _CPUSERDIR_LENGTH = _CPUSERDIR.length;

function _exportJSONObject (encoder: JSONEncoder) :myJsonType {

    // lacks surrounding {}
    let rawJson :Uint8Array = encoder.serialize();

    let json = new Uint8Array(2 + rawJson.length);

    json.set(rawJson, 1);
    json[0] = _OPEN_BRACE;
    json[json.length - 1] = _CLOSE_BRACE;

    return json.buffer;
}

function _getCBORPreface (majorType: u8, theNumber: u64) :binaryString {
    let uarr :binaryString;

    if (theNumber < 24) {
        uarr = new Uint8Array(1);
        uarr[0] = (majorType << 5) + (theNumber as u8);
    }
    else if (theNumber < 256) {
        uarr = new Uint8Array(2);
        uarr[0] = (majorType << 5) + 24;
        uarr[1] = theNumber as u8;
    }
    else if (theNumber < 65536) {
        uarr = new Uint8Array(3);
        uarr[0] = (majorType << 5) + 25;

        (new DataView(uarr.buffer)).setUint16(1, theNumber as u16);
    }
    else if (theNumber < 4294967296) {
        uarr = new Uint8Array(5);
        uarr[0] = (majorType << 5) + 26;

        (new DataView(uarr.buffer)).setUint32(1, theNumber as u32);
    }
    else {
        uarr = new Uint8Array(9);
        uarr[0] = (majorType << 5) + 27;

        (new DataView(uarr.buffer)).setUint64(1, theNumber as u64);
    }

    return uarr;
}

function _binaryKVArray2Buffer (theKVArray: binaryKVArray) :ArrayBuffer {
    let buflen :u32 = theKVArray.reduce<u32>(
        (a,b) => a + 1 + b.length,
        0
    );

    let uarr = new Uint8Array(buflen);
    let offset: i32 = 0;

    for (let i=0; i<theKVArray.length; i++) {
        uarr.set(theKVArray[i], offset);
        offset += 1 + theKVArray[i].length;
    }

    return uarr.buffer;
}

/*
function _binaryMap2Cbor (theMap: binaryMap) :myCborType {
    let keys :binaryString[] = theMap.keys();
    let values :binaryString[] = theMap.values();

    // Map preface, plus preface & data for each key & value
    let cborPieces = new StaticArray<binaryString>(1 + 4 * keys.length);

    cborPieces[0] = _getCBORPreface(5, keys.length);

    let cborLength :i32 = cborPieces[0].length;

    for (let k=0; k<keys.length; k++) {
        cborPieces[ 1 + k ] = _getCBORPreface(2, keys[k].length);
        cborLength += cborPieces[ 1 + k ].length;

        cborPieces[ 2 + k ] = keys[k];
        cborLength += cborPieces[ 2 + k ].length;

        cborPieces[ 3 + k ] = _getCBORPreface(2, values[k].length);
        cborLength += cborPieces[ 3 + k ].length;

        cborPieces[ 4 + k ] = values[k];
        cborLength += cborPieces[ 4 + k ].length;
    }

    let cbor = new Uint8Array(cborLength);
    let cborOffset :i32 = 0;

    for (let c=0; c<cborPieces.length; c++) {
        cbor.set( cborPieces[c], cborOffset );
        cborOffset += cborPieces[c].length;
    }

    return cbor.buffer;
}
*/

function _stringDict2Json(cpuser: cpuserType): myJsonType {
    let encoder = new JSONEncoder();

    let keys: string[] = cpuser.keys();

    for (let i=0; i<keys.length; i++) {
        let name: string = keys[i];
        encoder.setString(name, cpuser.get(name));
    }

    return _exportJSONObject(encoder);
}

function _populateCpuser(username: binaryString): cpuserType {
    let path :binaryString = new Uint8Array(_CPUSERDIR_LENGTH + username.length);
    path.set(_CPUSERDIR, 0);
    path.set(username, _CPUSERDIR_LENGTH);

    let buffer = slurp_binary(path.buffer);
    let bigStr :binaryString = Uint8Array.wrap(buffer);

    let offset :i32 = 0;

    let hashAt :i32;
    let equalAt :i32;
    let breakAt :i32;

    let cpuser :cpuserType = [];

    while (offset < bigStr.length) {
        breakAt = bigStr.indexOf(_NEWLINE, offset);
        if (breakAt === -1) breakAt = bigStr.length;

        let line = bigStr.subarray(offset, breakAt);

        offset += 1 + line.length;

        hashAt = line.indexOf(_OCTOTHORPE);
        if (-1 !== hashAt) {
            line = line.subarray(0, hashAt);
        }

        equalAt = line.indexOf(_EQUALS);
        if (-1 === equalAt) continue;

        //cpuser.set( line.subarray(0, equalAt), line.subarray(1 + equalAt) );
        cpuser.push( line.subarray(0, equalAt) );
        cpuser.push( line.subarray(1 + equalAt) );
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

    return cpuser;
}

/*
export function load_cpuser_file_CBOR (): myCborType {
    let cpuser = _populateCpuser(cpuser);

    return _binaryMap2Cbor(cpuser);
}

export function load_cpuser_file_JSON (): myJsonType {
    let cpuser = _populateCpuser(cpuser);

    return _stringDict2Json(cpuser);
}
*/

export function load_cpuser_file_KVBuffer(username: ArrayBuffer): ArrayBuffer {
    let cpuser = _populateCpuser(Uint8Array.wrap(username));

    return _binaryKVArray2Buffer(cpuser);
}
