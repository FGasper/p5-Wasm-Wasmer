import "wasi";

import { Descriptor, FileSystem } from "as-wasi";

type binaryString = Uint8Array;
type binaryKVArray = binaryString[];
type cpuserType = binaryKVArray;

@external("cpanel", "slurp_binary")
export declare function slurp_binary (path: ArrayBuffer): ArrayBuffer;

const _NEWLINE : u8 = '\n'.charCodeAt(0) as u8;
const _OCTOTHORPE : u8 = '#'.charCodeAt(0) as u8;
const _EQUALS : u8 = '='.charCodeAt(0) as u8;

const _CPUSERDIR : binaryString = Uint8Array.wrap( String.UTF8.encode("/var/cpanel/users/") );
const _CPUSERDIR_LENGTH = _CPUSERDIR.length;

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

function _populateCpuser(bigStr: binaryString): cpuserType {
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

        cpuser.push( line.subarray(0, equalAt) );
        cpuser.push( line.subarray(1 + equalAt) );
    }

    return cpuser;
}

/*
export function load_cpuser_file_wasi_KVBuffer(username: ArrayBuffer): ArrayBuffer {
    let path = "/var/cpanel/users/" + String.UTF8.decode(username);
    let fd_maybe :Descriptor|null = FileSystem.open(path, "r");
    if (!fd_maybe) throw new Error("Failed to open!");

    let fd = fd_maybe as Descriptor;

    let cpuser_content = fd.readAll() as u8[];

    let bigStr = new Uint8Array(cpuser_content.length);
    for (let i=0; i<bigStr.length; i++) bigStr[i] = cpuser_content[i];

    let cpuser = _populateCpuser(bigStr);

    return _binaryKVArray2Buffer(cpuser);
}
*/

export function load_cpuser_file_KVBuffer(username: ArrayBuffer): ArrayBuffer {
    let path :binaryString = new Uint8Array(_CPUSERDIR_LENGTH + username.byteLength);
    path.set(_CPUSERDIR, 0);
    path.set(Uint8Array.wrap(username), _CPUSERDIR_LENGTH);

    let buffer = slurp_binary(path.buffer);
    let bigStr :binaryString = Uint8Array.wrap(buffer);

    let cpuser = _populateCpuser(bigStr);

    return _binaryKVArray2Buffer(cpuser);
}
