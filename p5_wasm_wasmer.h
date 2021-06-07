#ifndef P5_WASM_WASMER_H
#define P5_WASM_WASMER_H 1

static inline SV* ptr_to_svrv (pTHX_ void* ptr, HV* stash) {
    SV* referent = newSVuv( PTR2UV(ptr) );
    SV* retval = newRV_noinc(referent);
    sv_bless(retval, stash);

    return retval;
}

static inline void* svrv_to_ptr (pTHX_ SV *self_sv) {
    SV *referent = SvRV(self_sv);
    return INT2PTR(void*, SvUV(referent));
}

void croak_if_non_null_not_derived (pTHX_ SV *obj, const char* classname) {
    if (obj && !sv_derived_from(obj, classname)) {
        croak("Give a %s instance, or nothing. (Gave: %" SVf ")", classname, obj);
    }
}

#endif
