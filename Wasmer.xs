#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <stdio.h>
#include <assert.h>
#include <stdbool.h>

#include <wasmer.h>
//#include <wasmer_wasm.h>

#define ENGINE_CLASS "Wasm::Wasmer::Engine"
#define INSTANCE_CLASS "Wasm::Wasmer::Instance"
#define WASI_INSTANCE_CLASS "Wasm::Wasmer::WasiInstance"
#define MEMORY_CLASS "Wasm::Wasmer::Memory"
#define FUNCTION_CLASS "Wasm::Wasmer::Function"

#define own

#ifdef MULTIPLICITY
#   define WASM_WASMER_MUST_STORE_PERL 1
#else
#   define WASM_WASMER_MUST_STORE_PERL 0
#endif

#define _DEBUG 1

typedef struct {
    wasm_store_t* store;

    union {
        wasm_engine_t* mine;
        SV* sv;
    } engine;

    bool engine_is_mine;
} store_holder_t;

typedef struct {
    wasm_module_t* module;
    SV* store_sv;

    wasm_exporttype_vec_t export_types;
} module_holder_t;

typedef struct {
    wasm_instance_t* instance;
    SV* module_sv;

    wasm_extern_vec_t exports;
} instance_holder_t;

typedef struct {
    wasm_memory_t* memory;
    wasm_exporttype_t* export_type;

    SV* instance_sv;
} memory_holder_t;

typedef struct {
    wasm_func_t* function;
    wasm_exporttype_t* export_type;

    SV* instance_sv;
} function_holder_t;

typedef struct {
    CV* coderef;

#if WASM_WASMER_MUST_STORE_PERL
    tTHX aTHX;
#endif

    wasm_store_t* store;

    wasm_name_t modname;
    wasm_name_t funcname;

    wasm_valtype_vec_t results;
} callback_holder_t;

static inline SV* _ptr_to_svrv(pTHX_ void* ptr, HV* stash) {
    SV* referent = newSVuv( PTR2UV(ptr) );
    SV* retval = newRV_noinc(referent);
    sv_bless(retval, stash);

    return retval;
}

static inline wasm_engine_t* _get_engine_from_sv(pTHX_ SV *self_sv) {
    SV *referent = SvRV(self_sv);
    return INT2PTR(wasm_engine_t*, SvUV(referent));
}

static inline store_holder_t* _get_store_holder_p_from_sv(pTHX_ SV *self_sv) {
    SV *referent = SvRV(self_sv);
    return INT2PTR(store_holder_t*, SvUV(referent));
}

static inline module_holder_t* _get_module_holder_p_from_sv(pTHX_ SV *self_sv) {
    SV *referent = SvRV(self_sv);
    return INT2PTR(module_holder_t*, SvUV(referent));
}

static inline instance_holder_t* _get_instance_holder_p_from_sv(pTHX_ SV *self_sv) {
    SV *referent = SvRV(self_sv);
    return INT2PTR(instance_holder_t*, SvUV(referent));
}

static inline memory_holder_t* _get_memory_holder_p_from_sv(pTHX_ SV *self_sv) {
    SV *referent = SvRV(self_sv);
    return INT2PTR(memory_holder_t*, SvUV(referent));
}

static inline function_holder_t* _get_function_holder_p_from_sv(pTHX_ SV *self_sv) {
    SV *referent = SvRV(self_sv);
    return INT2PTR(function_holder_t*, SvUV(referent));
}

/* ---------------------------------------------------------------------- */

void print_wasmer_error()
{
    int error_len = wasmer_last_error_length();
    printf("Error len: `%d`\n", error_len);
    char *error_str = malloc(error_len);
    wasmer_last_error_message(error_str, error_len);
    printf("Error str: `%s`\n", error_str);
}

/* ---------------------------------------------------------------------- */

// TODO: function creation

/* ---------------------------------------------------------------------- */

unsigned _call_wasm( pTHX_ SV** SP, wasm_func_t* function, wasm_exporttype_t* export_type, SV** given_arg, unsigned given_args_count ) {

    own wasm_functype_t* functype = wasm_func_type(function);

    const wasm_valtype_vec_t* params = wasm_functype_params(functype);
    const wasm_valtype_vec_t* results = wasm_functype_results(functype);

    unsigned params_count = params->size;
    unsigned results_count = results->size;

    wasm_valkind_t param_kind[given_args_count];
    wasm_valkind_t result_kind[results_count];

    for (unsigned i=0; i<given_args_count; i++) {
        param_kind[i] = wasm_valtype_kind(params->data[i]);
    }

    for (unsigned i=0; i<results_count; i++) {
        result_kind[i] = wasm_valtype_kind(results->data[i]);
    }

    wasm_functype_delete(functype);

    if (given_args_count > params_count) {
        const wasm_name_t* name = wasm_exporttype_name(export_type);

        croak("“%.*s” expects %u input(s); %u given", (int)name->size, name->data, params_count, given_args_count);
    }

    if ((results_count > 1) && GIMME_V == G_SCALAR) {
        const wasm_name_t* name = wasm_exporttype_name(export_type);

        croak("“%.*s” returns multiple values (%u); called in scalar context", (int)name->size, name->data, results_count);
    }

    wasm_val_t wasm_param[given_args_count];

    for (unsigned i=0; i<given_args_count; i++) {
        wasm_param[i].kind = param_kind[i];

        switch (param_kind[i]) {
            case WASM_I32:
                wasm_param[i].of.i32 = SvIV( given_arg[i] );
                break;

            case WASM_I64:
                wasm_param[i].of.i64 = SvIV( given_arg[i] );
                break;

            case WASM_F32:
                wasm_param[i].of.f32 = SvNV( given_arg[i] );
                break;

            case WASM_F64:
                wasm_param[i].of.f64 = SvNV( given_arg[i] );
                break;

            default:
                croak("Parameter #%d is of unknown type (%d)!", 1 + i, param_kind[i]);
        }
    }

    wasm_val_t wasm_result[results_count];
    for (unsigned i=0; i<results_count; i++) {
        wasm_val_t cur = WASM_INIT_VAL;
        wasm_result[i] = cur;
    }

    wasm_val_vec_t params_vec = WASM_ARRAY_VEC(wasm_param);
    wasm_val_vec_t results_vec = WASM_ARRAY_VEC(wasm_result);

    own wasm_trap_t* trap = wasm_func_call(function, &params_vec, &results_vec);

    if (trap != NULL) {
        wasm_name_t message;
        wasm_trap_message(trap, &message);

        SV* err_sv = newSVpv(message.data, 0);

        wasm_name_delete(&message);
        wasm_trap_delete(trap);

        // TODO: Exception object so it can contain the trap
        croak_sv(err_sv);
    }

    if (results_count) {
        EXTEND(SP, results_count);

        for (unsigned i=0; i<results_count; i++) {
            switch (result_kind[i]) {
                case WASM_I32:
                    mPUSHs( newSViv( (IV) wasm_result[i].of.i32 ) );
                    break;

                case WASM_I64:
                    mPUSHs( newSViv( (IV) wasm_result[i].of.i64 ) );
                    break;

                case WASM_F32:
                    mPUSHs( newSViv( (float) wasm_result[i].of.f32 ) );
                    break;

                case WASM_F64:
                    mPUSHs( newSViv( (float) wasm_result[i].of.f64 ) );
                    break;

                default:
                    croak("Function return #%d is of unknown type!", 1 + i);
            }
        }

    }

    return results_count;
}

static inline AV* _get_av_from_sv_or_croak (pTHX_ SV* sv, const char* description) {
    if (!SvROK(sv) || SVt_PVAV != SvTYPE(SvRV(sv))) {
        croak("%s must be an ARRAY reference, not `%" SVf "`", description, sv);
    }

    return (AV *) SvRV(sv);
}

CV* _get_import_coderef( pTHX_ AV* imports_av, const wasm_name_t* modname, const wasm_name_t* funcname ) {
    for (SSize_t i=0; i<=av_top_index(imports_av); i++) {
        SV** val = av_fetch(imports_av, i, 0);

        if (val == NULL) {
            croak("NULL found where ARRAY ref expected??");
        }

        if (!SvOK(*val)) {
            croak("Uninitialized value found where ARRAY ref expected??");
        }

        AV* import_av = _get_av_from_sv_or_croak( aTHX_ *val, "Import" );

        SV** el0 = av_fetch(import_av, 0, 0);

        SV **el1, **el2, **el3;

        if (el0 == NULL) {
            croak("NULL found at start of import??");
        }

        switch (SvUV(*el0)) {
            case WASM_EXTERN_FUNC: {
fprintf(stderr, "got a func import\n");
                    if (av_top_index(import_av) != 3) {
                        croak("Function imports should have exactly 3 arguments, not %ld", 1 + av_top_index(import_av));
                    }

                    el1 = av_fetch(import_av, 1, 0);

                    STRLEN perl_modname_len;
                    const char* perl_modname = SvPVbyte(*el1, perl_modname_len);

                    if (perl_modname_len != modname->size) break;
                    if (!memEQ(perl_modname, modname->data, modname->size)) break;
fprintf(stderr, "module name matches\n");

                    el2 = av_fetch(import_av, 2, 0);

                    STRLEN perl_funcname_len;
                    const char* perl_funcname = SvPVbyte(*el2, perl_funcname_len);

                    if (perl_funcname_len != funcname->size) break;
                    if (!memEQ(perl_funcname, funcname->data, funcname->size)) break;
fprintf(stderr, "func name matches\n");

                    el3 = av_fetch(import_av, 3, 0);
fprintf(stderr, "fetch 3\n");
                    if (!SvROK(*el3) || SVt_PVCV != SvTYPE(SvRV(*el3))) {
                        croak("Last arg to function import must be a coderef, not %" SVf, el3);
                    }

                    return (CV*) SvRV(*el3);
                }

                break;

            default:
                break;
        }
    }

    return NULL;
}

wasm_trap_t* host_func_callback( void* env, const wasm_val_vec_t* args, wasm_val_vec_t* results ) {
    callback_holder_t* callback_holder_p = (callback_holder_t*) env;

#if WASM_WASMER_MUST_STORE_PERL
    pTHX = callback_holder_p->aTHX;
#endif

    dSP;

    fprintf(stderr, "host_func_callback\n");

    if (args->size) {
        ENTER;
        SAVETMPS;
    }

    PUSHMARK(SP);

    if (args->size) {
        EXTEND(SP, args->size);

        for (unsigned i=0; i<args->size; i++) {
            SV* arg_sv;

            wasm_val_t arg = args->data[i];

            switch (arg.kind) {
                case WASM_I32:
                    arg_sv = newSViv( arg.of.i32 );
                    break;
                case WASM_I64:
                    arg_sv = newSViv( arg.of.i64 );
                    break;
                case WASM_F32:
                    arg_sv = newSVnv( arg.of.f32 );
                    break;
                case WASM_F64:
                    arg_sv = newSVnv( arg.of.f64 );
                    break;
                default:
                    arg_sv = NULL; /* silence warning */
                    assert(0);
            }

            mPUSHs(arg_sv);
        }

        PUTBACK;
    }

    I32 callflags = 0;

    switch (results->size) {
        case 0:
            callflags |= G_VOID;
            break;

        case 1:
            callflags |= G_SCALAR;
            break;

        default:
            callflags |= G_ARRAY;
    }

    /* Don’t trap exceptions … ?? */
    int got_count = call_sv( (SV*) callback_holder_p->coderef, callflags );

    SPAGAIN;

    if (got_count != results->size) {
        const char* msg = form(
            "%.*s.%.*s: expected %zu results but received %d",
            (int) callback_holder_p->modname.size,
            callback_holder_p->modname.data,
            (int) callback_holder_p->funcname.size,
            callback_holder_p->funcname.data,
            results->size,
            got_count
        );

        wasm_byte_vec_t vector;
        wasm_byte_vec_new(&vector, strlen(msg), (wasm_byte_t*) msg);

        wasm_trap_t* trap = wasm_trap_new(
            callback_holder_p->store,
            &vector
        );

        return trap;
    }

    for (I32 g=got_count-1; g >= 0; g--) {
        wasm_val_t* result = &results->data[g];

        result->kind = wasm_valtype_kind(callback_holder_p->results.data[g]);

        switch (result->kind) {
            case WASM_I32:
                result->of.i32 = (I32) POPi;
                break;
            case WASM_I64:
                result->of.i64 = (I64) POPi;
                break;
            case WASM_F32:
                result->of.f32 = (float) POPn;
                break;
            case WASM_F64:
                result->of.f64 = (double) POPn;
                break;

            default:
                assert(0);
        }
    }

    return NULL;
}

void free_callback_holder (void* env) {
    callback_holder_t* callback_holder_p = (callback_holder_t*) env;

#if WASM_WASMER_MUST_STORE_PERL
    pTHX = callback_holder_p->aTHX;
#endif

    SvREFCNT_dec((SV*) callback_holder_p->coderef);

    Safefree(callback_holder_p);
}

/* ---------------------------------------------------------------------- */

MODULE = Wasm::Wasmer     PACKAGE = Wasm::Wasmer

BOOT:
    newCONSTSUB(gv_stashpv("Wasm::Wasmer", 0), "WASM_EXTERN_FUNC", newSVuv(WASM_EXTERN_FUNC));

SV*
wat2wasm( SV* wat_sv )
    CODE:
        STRLEN watlen;
        const char* wat = SvPVbyte(wat_sv, watlen);

        wasm_byte_vec_t watvec;
        wasm_byte_vec_new(&watvec, watlen, wat);

        wasm_byte_vec_t wasmvec;

        wat2wasm(&watvec, &wasmvec);

        wasm_byte_vec_delete(&watvec);

        SV* ret = newSVpvn(wasmvec.data, wasmvec.size);

        wasm_byte_vec_delete(&wasmvec);

        RETVAL = ret;

    OUTPUT:
        RETVAL

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer     PACKAGE = Wasm::Wasmer::Engine

PROTOTYPES: DISABLE

SV*
new (SV* class_sv)
    CODE:
        if (!SvPOK(class_sv)) croak("Give a class name!");

        const char* class = SvPVbyte_nolen(class_sv);

        wasm_engine_t* engine = wasm_engine_new();

        RETVAL = _ptr_to_svrv(aTHX_ engine, gv_stashpv(class, FALSE));

    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        wasm_engine_t* engine = _get_engine_from_sv(aTHX_ self_sv);

        wasm_engine_delete(engine);

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer     PACKAGE = Wasm::Wasmer::Store

PROTOTYPES: DISABLE

SV*
new (SV* class_sv, SV* engine_sv=NULL)
    CODE:
        if (engine_sv && !sv_derived_from(engine_sv, ENGINE_CLASS)) {
            croak("Give a %s instance, or nothing. (Gave: %" SVf ")", ENGINE_CLASS, engine_sv);
        }

        if (!SvPOK(class_sv)) croak("Give a class name!");

        const char* class = SvPVbyte_nolen(class_sv);

        wasm_engine_t* engine = NULL;

        if (engine_sv == NULL) {
            engine = wasm_engine_new();
        }
        else {
            engine = _get_engine_from_sv(aTHX_ engine_sv);
        }

        wasm_store_t* store = wasm_store_new(engine);

        store_holder_t* store_holder_p;

        Newx(store_holder_p, 1, store_holder_t);

        store_holder_p->store = store;

        if (engine_sv == NULL) {
            store_holder_p->engine_is_mine = true;
            store_holder_p->engine.mine = engine;
        }
        else {
            store_holder_p->engine_is_mine = false;
            store_holder_p->engine.sv = SvRV(engine_sv);

            SvREFCNT_inc(store_holder_p->engine.sv);
        }

        RETVAL = _ptr_to_svrv(aTHX_ store_holder_p, gv_stashpv(class, FALSE));

    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        store_holder_t* store_holder_p = _get_store_holder_p_from_sv(aTHX_ self_sv);

        wasm_store_delete(store_holder_p->store);

        if (store_holder_p->engine_is_mine) {
            wasm_engine_delete(store_holder_p->engine.mine);
        }
        else {
            SvREFCNT_dec(store_holder_p->engine.sv);
        }

        Safefree(store_holder_p);

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer     PACKAGE = Wasm::Wasmer::Module

PROTOTYPES: DISABLE

SV*
new (SV* class_sv, SV* store_sv, SV* wasm_sv)
    CODE:
        if (!SvPOK(class_sv)) croak("Give a class name!");

        const char* class = SvPVbyte_nolen(class_sv);

        STRLEN wasm_len;
        char* wasm_bytes = SvPVbyte(wasm_sv, wasm_len);

        wasm_byte_vec_t binary;
        wasm_byte_vec_new(&binary, wasm_len, wasm_bytes);

        store_holder_t* store_holder_p = _get_store_holder_p_from_sv(aTHX_ store_sv);

        wasm_module_t* module = wasm_module_new(store_holder_p->store, &binary);

        wasm_byte_vec_delete(&binary);

        module_holder_t* module_holder_p;

        Newx(module_holder_p, 1, module_holder_t);

        module_holder_p->module = module;

        module_holder_p->store_sv = SvRV(store_sv);
        SvREFCNT_inc(module_holder_p->store_sv);

        wasm_module_exports(module, &module_holder_p->export_types);

        RETVAL = _ptr_to_svrv(aTHX_ module_holder_p, gv_stashpv(class, FALSE));

    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        module_holder_t* module_holder_p = _get_module_holder_p_from_sv(aTHX_ self_sv);

        wasm_module_delete(module_holder_p->module);
        wasm_exporttype_vec_delete(&module_holder_p->export_types);

        SvREFCNT_dec(module_holder_p->store_sv);

        Safefree(module_holder_p);

SV*
create_instance (SV* self_sv, SV* imports_sv=NULL)
    CODE:
        AV* imports_av = NULL;

        if (imports_sv) {
            if (SvOK(imports_sv)) {
                imports_av = _get_av_from_sv_or_croak( aTHX_ imports_sv, "Imports" );
            }
        }

        module_holder_t* module_holder_p = _get_module_holder_p_from_sv(aTHX_ self_sv);

        wasm_importtype_vec_t import_types;
        wasm_module_imports(module_holder_p->module, &import_types);

    SV* store_sv = module_holder_p->store_sv;
    store_holder_t* store_holder_p = INT2PTR(store_holder_t*, SvUV(store_sv));

        wasm_extern_t* externs[import_types.size];

        for (size_t i = 0; i < import_types.size; ++i) {
            const wasm_name_t* modname = wasm_importtype_module(import_types.data[i]);
            const wasm_name_t* name = wasm_importtype_name(import_types.data[i]);

            if (_DEBUG) {
                fprintf(stderr, "Import %zu: %.*s/%.*s\n", i, (int)modname->size, modname->data, (int)name->size, name->data);
            }

            const wasm_externtype_t* externtype = wasm_importtype_type(import_types.data[i]);

            switch (wasm_externtype_kind(externtype)) {
                case WASM_EXTERN_FUNC: {
                    CV* coderef = _get_import_coderef(aTHX_ imports_av, modname, name);

                    const wasm_functype_t* functype = wasm_externtype_as_functype_const(externtype);
                    const wasm_valtype_vec_t* params = wasm_functype_params(functype);
                    const wasm_valtype_vec_t* results = wasm_functype_results(functype);

                    callback_holder_t* callback_holder_p;

                    Newx(callback_holder_p, 1, callback_holder_t);

                    callback_holder_p->store = store_holder_p->store;
#if WASM_WASMER_MUST_STORE_PERL
                    callback_holder_p->aTHX = aTHX;
#endif
                    callback_holder_p->coderef = coderef;
                    SvREFCNT_inc( (SV*) coderef );
                    callback_holder_p->modname = *modname;
                    callback_holder_p->funcname = *name;

                    wasm_valtype_vec_copy(
                        &callback_holder_p->results,
                        results
                    );

                    own wasm_functype_t* host_func_type = wasm_functype_new((wasm_valtype_vec_t *) params, (wasm_valtype_vec_t *) results);

                    own wasm_func_t* host_func = wasm_func_new_with_env(
                        store_holder_p->store,
                        host_func_type,
                        host_func_callback,
                        callback_holder_p,
                        free_callback_holder
                    );
fprintf(stderr, "made func\n");

                    wasm_functype_delete(host_func_type);

                    externs[i] = wasm_func_as_extern(host_func);
                } break;

                default:
                    croak("Unhandled import type: %d\n", wasm_externtype_kind(externtype));
                    break;
            }
        }

        own wasm_extern_vec_t imports = WASM_ARRAY_VEC(externs);
        wasm_trap_t* traps = NULL;

        own wasm_instance_t* instance = wasm_instance_new(
            NULL, /* Ignored, per the documentation */
            module_holder_p->module,
            &imports,
            &traps
        );

        for (unsigned i=0; i<import_types.size; i++) {
            wasm_func_t* func = wasm_extern_as_func(externs[i]);
            wasm_func_delete(func);
        }

        // TODO: cleaner
        assert(instance);

        instance_holder_t* instance_holder_p;

        Newx(instance_holder_p, 1, instance_holder_t);

        instance_holder_p->instance = instance;
        instance_holder_p->module_sv = self_sv;

        wasm_instance_exports(instance, &instance_holder_p->exports);

        SvREFCNT_inc(self_sv);

        RETVAL = _ptr_to_svrv(aTHX_ instance_holder_p, gv_stashpv(INSTANCE_CLASS, FALSE));

    OUTPUT:
        RETVAL

SV*
create_wasi_instance (SV* self_sv, SV* imports_sv=NULL)
    CODE:
        if (imports_sv != NULL && SvOK(imports_sv)) {
            croak("Imports are unsupported for now.");
        }
    fprintf(stderr, "in create_wasi_instance\n");

        module_holder_t* module_holder_p = _get_module_holder_p_from_sv(aTHX_ self_sv);
    SV* store_sv = module_holder_p->store_sv;
    store_holder_t* store_holder_p = INT2PTR(store_holder_t*, SvUV(store_sv));

        wasm_trap_t* traps = NULL;

    wasi_config_t* config = wasi_config_new("my-program");

  const char* js_string = "function greet(name) { return JSON.stringify('Hello, ' + name); }; print(greet('World'));";
  wasi_config_arg(config, "--eval");
  wasi_config_arg(config, js_string);

    wasi_config_inherit_stderr(config);
    wasi_config_inherit_stdout(config);
    wasi_env_t* wasi_env = wasi_env_new(config);

    wasm_importtype_vec_t import_types;
    wasm_module_imports(module_holder_p->module, &import_types);

    wasm_extern_vec_t imports;
    wasm_extern_vec_new_uninitialized(&imports, import_types.size);
    wasm_importtype_vec_delete(&import_types);

    fprintf(stderr, "before get imports\n");
    bool get_imports_result = wasi_get_imports(store_holder_p->store, module_holder_p->module, wasi_env, &imports);
  if (!get_imports_result) {
    print_wasmer_error();
    croak("> Error getting WASI imports!\n");
  }

        wasm_instance_t* instance = wasm_instance_new(
            NULL, /* Ignored, per the documentation */
            module_holder_p->module,
            &imports,
            &traps
        );

        // TODO: cleaner
        assert(instance);

        instance_holder_t* instance_holder_p;

        Newx(instance_holder_p, 1, instance_holder_t);

        instance_holder_p->instance = instance;
        instance_holder_p->module_sv = self_sv;

        wasm_instance_exports(instance, &instance_holder_p->exports);

        SvREFCNT_inc(self_sv);

        RETVAL = _ptr_to_svrv(aTHX_ instance_holder_p, gv_stashpv(WASI_INSTANCE_CLASS, FALSE));

    OUTPUT:
        RETVAL

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer     PACKAGE = Wasm::Wasmer::Instance

PROTOTYPES: DISABLE

void
export_memories (SV* self_sv)
    PPCODE:
        if (GIMME_V != G_ARRAY) croak("List context only!");

        instance_holder_t* instance_holder_p = _get_instance_holder_p_from_sv(aTHX_ self_sv);

        module_holder_t* module_holder_p = _get_module_holder_p_from_sv(aTHX_ instance_holder_p->module_sv);

        wasm_exporttype_vec_t* export_types = &module_holder_p->export_types;

        wasm_extern_vec_t* exports = &instance_holder_p->exports;

        unsigned return_count = 0;

        SV* possible_memory_sv[exports->size];

        for (unsigned i = 0; i<exports->size; i++) {
            if (wasm_extern_kind(exports->data[i]) != WASM_EXTERN_MEMORY)
                continue;

            memory_holder_t* memory_holder;
            Newx(memory_holder, 1, memory_holder_t);

            wasm_memory_t* memory = wasm_extern_as_memory(exports->data[i]);

            memory_holder->memory = memory;
            memory_holder->export_type = export_types->data[i];

            memory_holder->instance_sv = SvRV(self_sv);
            SvREFCNT_inc(memory_holder->instance_sv);

            possible_memory_sv[return_count] = _ptr_to_svrv( aTHX_
                memory_holder,
                gv_stashpv(MEMORY_CLASS, FALSE)
            );

            return_count++;
        }

        if (return_count) {
            EXTEND(SP, return_count);

            for (unsigned i=0; i<return_count; i++)
                mPUSHs(possible_memory_sv[i]);

            XSRETURN(return_count);
        }
        else {
            XSRETURN_EMPTY;
        }

void
export_functions (SV* self_sv)
    PPCODE:
        if (GIMME_V != G_ARRAY) croak("List context only!");

        instance_holder_t* instance_holder_p = _get_instance_holder_p_from_sv(aTHX_ self_sv);

        module_holder_t* module_holder_p = _get_module_holder_p_from_sv(aTHX_ instance_holder_p->module_sv);

        wasm_exporttype_vec_t* export_types = &module_holder_p->export_types;

        wasm_extern_vec_t* exports = &instance_holder_p->exports;

        unsigned return_count = 0;

        SV* possible_function_sv[exports->size];

        for (unsigned i = 0; i<exports->size; i++) {
            if (wasm_extern_kind(exports->data[i]) != WASM_EXTERN_FUNC)
                continue;

            function_holder_t* function_holder;
            Newx(function_holder, 1, function_holder_t);

            wasm_func_t* function = wasm_extern_as_func(exports->data[i]);

            function_holder->function = function;
            function_holder->export_type = export_types->data[i];

            function_holder->instance_sv = SvRV(self_sv);
            SvREFCNT_inc(function_holder->instance_sv);

            possible_function_sv[return_count] = _ptr_to_svrv( aTHX_
                function_holder,
                gv_stashpv(FUNCTION_CLASS, FALSE)
            );

            return_count++;
        }

        if (return_count) {
            EXTEND(SP, return_count);

            for (unsigned i=0; i<return_count; i++)
                mPUSHs(possible_function_sv[i]);

            XSRETURN(return_count);
        }
        else {
            XSRETURN_EMPTY;
        }


void
call (SV* self_sv, SV* funcname_sv, ...)
    PPCODE:
        STRLEN funcname_len;
        const char* funcname = SvPVbyte(funcname_sv, funcname_len);

        unsigned given_args_count = items - 2;

        instance_holder_t* instance_holder_p = _get_instance_holder_p_from_sv(aTHX_ self_sv);

        module_holder_t* module_holder_p = _get_module_holder_p_from_sv(aTHX_ instance_holder_p->module_sv);

        wasm_exporttype_vec_t* export_types = &module_holder_p->export_types;

        wasm_extern_vec_t* exports = &instance_holder_p->exports;

        for (unsigned i = 0; i<exports->size; i++) {
            if (wasm_extern_kind(exports->data[i]) != WASM_EXTERN_FUNC)
                continue;

            const wasm_name_t* name = wasm_exporttype_name(export_types->data[i]);

            if (funcname_len != name->size) continue;
            if (!memEQ(name->data, funcname, funcname_len)) continue;

            /* Yay! We found our function. */

            wasm_exporttype_t* export_type = export_types->data[i];
            wasm_func_t* func = wasm_extern_as_func(exports->data[i]);

            unsigned retvals = _call_wasm( aTHX_ SP, func, export_type, &ST(2), given_args_count );

            XSRETURN(retvals);
        }

        croak("No function named “%" SVf "” exists!", funcname_sv);

void
DESTROY (SV* self_sv)
    CODE:
        instance_holder_t* instance_holder_p = _get_instance_holder_p_from_sv(aTHX_ self_sv);

        wasm_instance_delete(instance_holder_p->instance);
        wasm_extern_vec_delete(&instance_holder_p->exports);

        SvREFCNT_dec(instance_holder_p->module_sv);

        Safefree(instance_holder_p);

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer       PACKAGE = Wasm::Wasmer::Memory

SV*
name (SV* self_sv)
    CODE:
        memory_holder_t* memory_holder_p = _get_memory_holder_p_from_sv(aTHX_ self_sv);

        const wasm_name_t* name = wasm_exporttype_name(memory_holder_p->export_type);

        RETVAL = newSVpvn( name->data, name->size );

    OUTPUT:
        RETVAL

UV
data (SV* self_sv)
    CODE:
        memory_holder_t* memory_holder_p = _get_memory_holder_p_from_sv(aTHX_ self_sv);

        RETVAL = (UV) wasm_memory_data( memory_holder_p->memory );

    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        memory_holder_t* memory_holder_p = _get_memory_holder_p_from_sv(aTHX_ self_sv);
        SvREFCNT_dec( memory_holder_p->instance_sv );

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer       PACKAGE = Wasm::Wasmer::Function

void
DESTROY (SV* self_sv)
    CODE:
        function_holder_t* function_holder_p = _get_function_holder_p_from_sv(aTHX_ self_sv);
        SvREFCNT_dec( function_holder_p->instance_sv );

SV*
name (SV* self_sv)
    CODE:
        function_holder_t* function_holder_p = _get_function_holder_p_from_sv(aTHX_ self_sv);

        const wasm_name_t* name = wasm_exporttype_name(function_holder_p->export_type);

        RETVAL = newSVpvn( name->data, name->size );

    OUTPUT:
        RETVAL

void
call (SV* self_sv, ...)
    PPCODE:
        function_holder_t* function_holder_p = _get_function_holder_p_from_sv(aTHX_ self_sv);

        unsigned count = _call_wasm( aTHX_ SP, function_holder_p->function, function_holder_p->export_type, &ST(1), items - 1 );

        XSRETURN(count);

# void
# inputs (SV* self_sv)
#     PPCODE:
#         function_holder_t* function_holder_p = _get_function_holder_p_from_sv(aTHX_ self_sv);
# 
#         const wasm_externtype_t* externtype = wasm_exporttype_type(&function_holder_p->export_type);
# 
#         const wasm_functype_t* functype = wasm_externtype_as_functype_const(externtype);
# 
#         const wasm_valtype_vec_t* params = wasm_functype_params(functype);
# 
#         unsigned params_count = params->size;
# 
#         EXTEND(SP, 2);
# 
#         for (unsigned i=0; i<params_count; i++)
#             mPUSHu( wasm_valtype_kind(params->data[i]) );
# 
#         XSRETURN(params_count);

# ----------------------------------------------------------------------

