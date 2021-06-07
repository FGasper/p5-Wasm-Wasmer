#ifndef P5_WASM_WASMER_H
#define P5_WASM_WASMER_H 1

#define _IN_GLOBAL_DESTRUCTION (PL_phase == PERL_PHASE_DESTRUCT)

#define warn_destruct_if_needed(sv, startpid) STMT_START { \
    if (_IN_GLOBAL_DESTRUCTION && (getpid() == startpid)) warn( \
        "%" SVf " destroyed at global destruction; memory leak likely!", \
        sv \
    ); \
} STMT_END

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

static inline AV* get_av_from_sv_or_croak (pTHX_ SV* sv, const char* description) {
    if (!SvROK(sv) || SVt_PVAV != SvTYPE(SvRV(sv))) {
        croak("%s must be an ARRAY reference, not `%" SVf "`", description, sv);
    }

    return (AV *) SvRV(sv);
}

#endif
