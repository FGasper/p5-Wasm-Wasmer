#ifndef P5_WASM_WASMER_H
#define P5_WASM_WASMER_H 1

#define _IN_GLOBAL_DESTRUCTION (PL_phase == PERL_PHASE_DESTRUCT)

#define warn_destruct_if_needed(sv, startpid) STMT_START { \
    if (_IN_GLOBAL_DESTRUCTION && (getpid() == startpid)) warn( \
        "%" SVf " destroyed at global destruction; memory leak likely!", \
        sv \
    ); \
} STMT_END

typedef struct {
    enum wasm_externkind_enum kind;
    const char* description;
} my_export_description_t;

static my_export_description_t export_descriptions[] = {
    { .kind = WASM_EXTERN_FUNC, .description = "function" },
    { .kind = WASM_EXTERN_GLOBAL, .description = "global" },
    { .kind = WASM_EXTERN_MEMORY, .description = "memory" },
    { .kind = WASM_EXTERN_TABLE, .description = "table" },
};

static inline const char* get_externkind_description(enum wasm_externkind_enum kind) {
    unsigned total = sizeof(export_descriptions) / sizeof(my_export_description_t);
    for (unsigned t=0; t<total; t++) {
        if (kind == export_descriptions[t].kind) {
            return export_descriptions[t].description;
        }
    }

    assert(0 && "No description for extern type?!?");
    return NULL;    // silence compiler warning
}

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

void _croak_if_wasmer_error(pTHX) {
    int wasmer_errlen = wasmer_last_error_length();
    if (wasmer_errlen > 0) {
        char msg[wasmer_errlen];
        wasmer_last_error_message(msg, wasmer_errlen);

        croak("Wasmer error: %.*s", wasmer_errlen, msg);
    }
}

void _croak_if_trap (pTHX_ wasm_trap_t* trap) {
    if (trap != NULL) {
        wasm_name_t message;
        wasm_trap_message(trap, &message);

        wasm_frame_t* origin = wasm_trap_origin(trap);

        SV* err_sv;

        if (origin) {
            err_sv = newSVpvf(
                "Wasmer trap: %.*s (func %u offset %zu)",
                (int) message.size,
                message.data,
                wasm_frame_func_index(origin),
                wasm_frame_func_offset(origin)
            );

            wasm_frame_delete(origin);
        }
        else {
            err_sv = newSVpvf(
                "Wasmer trap: %.*s",
                (int) message.size,
                message.data
            );
        }

        wasm_name_delete(&message);
        wasm_trap_delete(trap);

        // TODO: Exception object so it can contain the trap
        croak_sv(err_sv);
    }
}

// This really ought to be in Perl’s API, or some standard XS toolkit …
static inline IV grok_iv (pTHX_ SV* sv) {
    if (SvIOK_notUV(sv)) return SvIV(sv);

    UV myuv;

    if (SvUOK(sv)) {
        myuv = SvUV(sv);
        if (myuv <= IV_MAX) return myuv;

        croak("%" SVf " cannot be signed (max=%" IVdf ")!", sv, IV_MAX);
    }

    STRLEN len;
    const char* str = SvPVbyte(sv, len);

    int flags = grok_number(str, len, &myuv);

    if (!flags || (flags & IS_NUMBER_NAN)) {
        croak("%" SVf " cannot be a number!", sv);
    }

    if (flags & IS_NUMBER_GREATER_THAN_UV_MAX) {
        croak("%" SVf " exceeds numeric limit (%" UVuf ")!", sv, UV_MAX);
    }

    if (!(flags & IS_NUMBER_IN_UV)) {
        croak("%" SVf " cannot be a number!", sv);
    }

    if (flags & IS_NUMBER_NOT_INT) {
        croak("%" SVf " cannot be an integer!", sv);
    }


    if (flags & IS_NUMBER_NEG) {

        // myuv is the absolute value.
        if (-myuv < IV_MIN) {
            croak("%" SVf " is too low to be signed on this system (min=%" IVdf ")!", sv, IV_MIN);
        }

        return -myuv;
    }

    if (myuv > IV_MAX) {
        croak("%" SVf " exceeds this system's maximum signed integer (max=%" IVdf ")!", sv, IV_MAX);
    }

    return myuv;
}

static inline I32 grok_i32 (pTHX_ SV* sv) {
    IV myiv = grok_iv(aTHX_ sv);

    if (myiv > I32_MAX) {
        croak("%" SVf " exceeds i32's maximum (%d)!", sv, I32_MAX);
    }

    if (myiv < I32_MIN) {
        croak("%" SVf " is less than i32's minimum (%d)!", sv, I32_MIN);
    }

    return myiv;
}

static_assert(sizeof(IV) == sizeof(I64), "IV == I64");
#define grok_i64 grok_iv

#endif
