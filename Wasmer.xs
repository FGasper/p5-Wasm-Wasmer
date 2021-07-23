#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <stdio.h>
#include <assert.h>
#include <stdbool.h>

#include <wasmer.h>
//#include <wasmer_wasm.h>

#define own

#ifdef MULTIPLICITY
#   define WASM_WASMER_MUST_STORE_PERL 1
#else
#   define WASM_WASMER_MUST_STORE_PERL 0
#endif

#define _DEBUG 1

#define WASI_CLASS "Wasm::Wasmer::WASI"

#define EXTERN_CLASS "Wasm::Wasmer::Extern"
#define GLOBAL_CLASS "Wasm::Wasmer::Global"
#define MEMORY_CLASS "Wasm::Wasmer::Memory"
#define FUNCTION_CLASS "Wasm::Wasmer::Function"

#include "p5_wasm_wasmer.h"
#include "wasmer_engine.xsc"
#include "wasmer_store.xsc"
#include "wasmer_module.xsc"
#include "wasmer_instance.xsc"
#include "wasmer_function.xsc"
#include "wasmer_memory.xsc"
#include "wasmer_global.xsc"
#include "wasmer_wasi.xsc"

#define _ptr_to_svrv ptr_to_svrv

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

unsigned _call_wasm( pTHX_ SV** SP, wasm_func_t* function, SV** given_arg, unsigned given_args_count ) {

    own wasm_functype_t* functype = wasm_func_type(function);

    const wasm_valtype_vec_t* params = wasm_functype_params(functype);
    const wasm_valtype_vec_t* results = wasm_functype_results(functype);

    unsigned params_count = params->size;
    unsigned results_count = results->size;

    wasm_valkind_t param_kind[given_args_count];

    for (unsigned i=0; i<params->size; i++) {
        param_kind[i] = wasm_valtype_kind(params->data[i]);
    }

    wasm_functype_delete(functype);

    if (given_args_count != params_count) {
        croak("Function needs %u parameter(s); %u given", params_count, given_args_count);
    }

    if ((results_count > 1) && GIMME_V == G_SCALAR) {
        croak("Function returns multiple values (%u); called in scalar context", results_count);
    }

    wasm_val_t wasm_param[given_args_count];

    for (unsigned i=0; i<given_args_count; i++) {
        wasm_param[i] = grok_wasm_val(aTHX_ param_kind[i], given_arg[i]);
    }

    wasm_val_t wasm_result[results_count];
    for (unsigned i=0; i<results_count; i++) {
        wasm_val_t cur = WASM_INIT_VAL;
        wasm_result[i] = cur;
    }

    wasm_val_vec_t params_vec = WASM_ARRAY_VEC(wasm_param);
    wasm_val_vec_t results_vec = WASM_ARRAY_VEC(wasm_result);

    own wasm_trap_t* trap = wasm_func_call(function, &params_vec, &results_vec);

    _croak_if_trap(aTHX_ trap);

    if (results_count) {
        EXTEND(SP, results_count);

        for (unsigned i=0; i<results_count; i++) {
            mPUSHs( ww_val2sv( aTHX_ &wasm_result[i] ) );
        }
    }

    return results_count;
}

static inline void _start_wasi_if_needed(pTHX_ instance_holder_t* instance_holder_p) {
    if (!instance_holder_p->wasi_sv) return;

    if (instance_holder_p->wasi_started) return;

    instance_holder_p->wasi_started = true;

    wasm_func_t* func = wasi_get_start_function(instance_holder_p->instance);

    wasm_val_t args_val[] = {};
    wasm_val_t results_val[] = {};
    wasm_val_vec_t args = WASM_ARRAY_VEC(args_val);
    wasm_val_vec_t results = WASM_ARRAY_VEC(results_val);

    own wasm_trap_t* trap = wasm_func_call(func, &args, &results);

    _croak_if_trap(aTHX_ trap);
}

static inline void _wasi_config_delete( wasi_config_t* config ) {
    wasi_env_t* wasienv = wasi_env_new(config);
    wasi_env_delete(wasienv);
}

typedef SV* (*export_to_sv_fp)(pTHX_ SV*, wasm_extern_t*);

static inline export_to_sv_fp get_export_to_sv_fp (wasm_externkind_t kind) {
    export_to_sv_fp fp = (
        (kind == WASM_EXTERN_FUNC) ? function_to_sv :
        (kind == WASM_EXTERN_MEMORY) ? memory_to_sv :
        (kind == WASM_EXTERN_GLOBAL) ? global_to_sv :
        NULL
    );

    if (!fp) assert(0);

    return fp;
}

static unsigned xs_export_kind_list (pTHX_ SV** SP, SV* self_sv, wasm_externkind_t kind) {
    if (GIMME_V != G_ARRAY) croak("List context only!");

    instance_holder_t* instance_holder_p = svrv_to_ptr(aTHX_ self_sv);

    module_holder_t* module_holder_p = svrv_to_ptr(aTHX_ instance_holder_p->module_sv);

    wasm_exporttype_vec_t* export_types = &module_holder_p->export_types;

    wasm_extern_vec_t* exports = &instance_holder_p->exports;

    unsigned return_count = 0;

    SV* possible_export_sv[exports->size];

    export_to_sv_fp export_to_sv = get_export_to_sv_fp(kind);

    HV* ret = newHV();

    sv_2mortal( (SV*) ret );

    for (unsigned i = 0; i<exports->size; i++) {
        if (wasm_extern_kind(exports->data[i]) != kind)
            continue;

        const wasm_name_t* name = wasm_exporttype_name(export_types->data[i]);

        hv_store(ret, name->data, -name->size,
            export_to_sv( aTHX_
                module_holder_p->store_sv,
                exports->data[i]
            ),
            0
        );

        return_count++;
    }

    if (return_count) {
        EXTEND(SP, return_count);

        for (unsigned i=0; i<return_count; i++)
            mPUSHs(possible_export_sv[i]);
    }

    return return_count;
}

/* ---------------------------------------------------------------------- */

MODULE = Wasm::Wasmer     PACKAGE = Wasm::Wasmer

BOOT:
    newCONSTSUB(gv_stashpv("Wasm::Wasmer", 0), "WASM_CONST", newSVuv(WASM_CONST));
    newCONSTSUB(gv_stashpv("Wasm::Wasmer", 0), "WASM_VAR", newSVuv(WASM_VAR));

SV*
wat2wasm ( SV* wat_sv )
    CODE:
        STRLEN watlen;
        const char* wat = SvPVutf8(wat_sv, watlen);

        wasm_byte_vec_t watvec;
        wasm_byte_vec_new(&watvec, watlen, wat);

        wasm_byte_vec_t wasmvec;

        wat2wasm(&watvec, &wasmvec);

        wasm_byte_vec_delete(&watvec);

        if (wasmvec.size > 0) {
            SV* ret = newSVpvn(wasmvec.data, wasmvec.size);

            wasm_byte_vec_delete(&wasmvec);

            RETVAL = ret;
        }
        else {
            wasm_byte_vec_delete(&wasmvec);

            _croak_if_wasmer_error("Failed to convert WAT to WASM");

            croak("wat2wasm failed but left no message!");
        }

    OUTPUT:
        RETVAL

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer     PACKAGE = Wasm::Wasmer::Store

PROTOTYPES: DISABLE

SV*
new (SV* class_sv, ...)
    CODE:
        if (!SvPOK(class_sv)) croak("Give a class name!");

        unsigned argscount = items - 1;

        if (argscount % 2) {
            croak("%" SVf "::new: Uneven args list!", class_sv);
        }

        RETVAL = create_store_sv(aTHX_ class_sv, &ST(1), argscount);

    OUTPUT:
        RETVAL

SV*
create_i32_const (SV* self_sv, SV* value_sv)
    ALIAS:
        create_i32_mut =   1
        create_i64_const = 2
        create_i64_mut =   3
        create_f32_const = 4
        create_f32_mut =   5
        create_f64_const = 6
        create_f64_mut =   7
    CODE:
        const wasm_globaltype_t* global_ix2globaltype[] = {
            wasm_globaltype_new(wasm_valtype_new(WASM_I32), WASM_CONST),
            wasm_globaltype_new(wasm_valtype_new(WASM_I32), WASM_VAR),
            wasm_globaltype_new(wasm_valtype_new(WASM_I64), WASM_CONST),
            wasm_globaltype_new(wasm_valtype_new(WASM_I64), WASM_VAR),
            wasm_globaltype_new(wasm_valtype_new(WASM_F32), WASM_CONST),
            wasm_globaltype_new(wasm_valtype_new(WASM_F32), WASM_VAR),
            wasm_globaltype_new(wasm_valtype_new(WASM_F64), WASM_CONST),
            wasm_globaltype_new(wasm_valtype_new(WASM_F64), WASM_VAR),
        };

        const wasm_globaltype_t* gtype = global_ix2globaltype[ix];

        const wasm_valkind_t kind = wasm_valtype_kind(
            wasm_globaltype_content(gtype)
        );

        wasm_val_t val = grok_wasm_val(kind, value_sv);

        store_holder_t* store_holder_p = svrv_to_ptr(aTHX_ self_sv);

        wasm_global_t* global = wasm_global_new(
            store_holder_p->store,
            gtype,
            &val
        );
        if (!global) {
            _croak_if_wasmer_error("Failed to create global");
            assert(0 /* Failed to create global */);
        }

        RETVAL = global_to_sv( aTHX_
            self_sv,
            wasm_global_as_extern(global)
        );

    OUTPUT:
        RETVAL

SV*
create_memory (SV* self_sv, ...)
    CODE:
        PERL_UNUSED_ARG(self_sv);

        if (!(items % 2)) croak("Uneven args list given!");

        wasm_limits_t limits = {
            .max = wasm_limits_max_default,
        };
        bool saw_initial = false;

        for (I32 i=1; i<items; i += 2) {
            const char* arg = SvPVbyte_nolen(ST(i));

            if (strEQ(arg, "initial")) {
                limits.min = grok_i32(ST(1 + i));
                saw_initial = true;
            }
            else if (strEQ(arg, "maximum")) {
                limits.max = grok_i32(ST(1 + i));
            }
            else {
                croak("Unrecognized: %" SVf, ST(i));
            }
        }

        if (!saw_initial) croak("Need `initial`");

        RETVAL = new_memory_import_sv(aTHX_ self_sv, &limits);

    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        destroy_store_sv(aTHX_ self_sv);

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer     PACKAGE = Wasm::Wasmer::Module

PROTOTYPES: DISABLE

SV*
new (SV* class_sv, SV* wasm_sv, SV* store_sv=NULL)
    CODE:
        croak_if_non_null_not_derived(aTHX_ store_sv, P5_WASM_WASMER_STORE_CLASS);
        if (!SvPOK(class_sv)) croak("Give a class name!");

        RETVAL = create_module_sv(aTHX_ class_sv, wasm_sv, store_sv);

    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        destroy_module_sv(aTHX_ self_sv);

SV*
create_instance (SV* self_sv, SV* imports_sv=NULL)
    CODE:
        RETVAL = create_instance_sv(aTHX_ NULL, self_sv, imports_sv, NULL);

    OUTPUT:
        RETVAL

SV*
serialize (SV* self_sv)
    CODE:
        module_holder_t* module_holder_p = svrv_to_ptr(aTHX_ self_sv);

        wasm_byte_vec_t binary;

        wasm_module_serialize( module_holder_p->module, &binary );

        SV* ret = newSVpvn(binary.data, binary.size);

        wasm_byte_vec_delete(&binary);

        RETVAL = ret;

    OUTPUT:
        RETVAL

SV*
deserialize (SV* bytes_sv, SV* store_sv=NULL)
    CODE:
        STRLEN byteslen;
        const char* bytes = SvPVbyte(bytes_sv, byteslen);

        if (store_sv) {
            SvREFCNT_inc(store_sv);
        }
        else {
            store_sv = create_store_sv(aTHX_ NULL, NULL, 0);
        }

        store_holder_t* store_holder_p = svrv_to_ptr(aTHX_ store_sv);

        wasm_byte_vec_t vector;
        wasm_byte_vec_new(&vector, byteslen, (wasm_byte_t*) bytes);

        wasm_module_t* module = wasm_module_deserialize( store_holder_p->store, &vector );

        wasm_byte_vec_delete(&vector);

        if (!module) croak("Failed to deserialize module!");

        RETVAL = module_to_sv(aTHX_ module, store_sv, P5_WASM_WASMER_MODULE_CLASS);

    OUTPUT:
        RETVAL

bool
validate (SV* wasm_sv, SV* store_sv_in=NULL)
    CODE:
        STRLEN wasmlen;
        const wasm_byte_t* wasmbytes = SvPVbyte(wasm_sv, wasmlen);

        SV* store_sv;

        if (store_sv_in) {
            store_sv = store_sv_in;
        }
        else {
            store_sv = create_store_sv(aTHX_ NULL, NULL, 0);
            sv_2mortal(store_sv);
        }

        store_holder_t* store_holder_p = svrv_to_ptr(aTHX_ store_sv);

        wasm_byte_vec_t wasm;
        wasm_byte_vec_new( &wasm, wasmlen, wasmbytes );

        RETVAL = wasm_module_validate(store_holder_p->store, &wasm);

        wasm_byte_vec_delete(&wasm);

    OUTPUT:
        RETVAL

SV*
create_wasi_instance (SV* self_sv, SV* wasi_sv=NULL, SV* imports_sv=NULL)
    CODE:
        if (NULL == wasi_sv || !SvOK(wasi_sv)) {
            wasi_config_t* config = wasi_config_new("");
            wasi_env_t* wasienv = wasi_env_new(config);
            wasi_holder_t* holder = wasi_env_to_holder(aTHX_ wasienv);

            wasi_sv = ptr_to_svrv(aTHX_ holder, gv_stashpv(WASI_CLASS, FALSE));

            sv_2mortal(wasi_sv);
        }
        else if (!sv_derived_from(wasi_sv, WASI_CLASS)) {
            croak("Give a %s instance, not %" SVf "!", WASI_CLASS, wasi_sv);
        }

        wasi_holder_t* wasi_holder_p = svrv_to_ptr(aTHX_ wasi_sv);
        wasi_env_t* wasi_env_p = wasi_holder_p->env;

        module_holder_t* module_holder_p = svrv_to_ptr(aTHX_ self_sv);
        SV* store_sv = module_holder_p->store_sv;
        store_holder_t* store_holder_p = svrv_to_ptr(aTHX_ store_sv);

        wasmer_named_extern_vec_t host_imports;

        /*
            XXX: This function is unstable & non-standard, but it’s the
            only way currently to mix WASI imports with host functions.
        */
        bool get_imports_result = wasi_get_unordered_imports(
            store_holder_p->store,
            module_holder_p->module,
            wasi_env_p,
            &host_imports
        );

        if (!get_imports_result) {
            print_wasmer_error();
            croak("> Error getting WASI imports!\n");
        }

        SV* instance_sv = create_instance_sv(aTHX_ NULL, self_sv, imports_sv, &host_imports);

        instance_holder_t* instance_holder_p = svrv_to_ptr(aTHX_ instance_sv);
        instance_holder_p->wasi_sv = wasi_sv;
        SvREFCNT_inc(wasi_sv);

        RETVAL = instance_sv;

    OUTPUT:
        RETVAL

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer     PACKAGE = Wasm::Wasmer::Instance

PROTOTYPES: DISABLE

SV*
export_names_ar (SV* self_sv)
    CODE:
        instance_holder_t* instance_holder_p = svrv_to_ptr(aTHX_ self_sv);

        module_holder_t* module_holder_p = svrv_to_ptr(aTHX_ instance_holder_p->module_sv);

        wasm_exporttype_vec_t* export_types = &module_holder_p->export_types;

        AV* ret = newAV();
        sv_2mortal( (SV*) ret );

        if (export_types->size) {
            av_extend(ret, export_types->size - 1);

            for (unsigned i = 0; i < export_types->size; i++) {
                const wasm_name_t* name = wasm_exporttype_name(export_types->data[i]);
                SV* newsv = newSVpvn_flags(name->data, name->size, SVf_UTF8);
            sv_dump(newsv);
                av_store(ret, i, newsv);
            }
        }

        SvREFCNT_inc( (SV*) ret );

        RETVAL = newRV_inc( (SV*) ret);

    OUTPUT:
        RETVAL

SV*
export (SV* self_sv, SV* search_name)
    CODE:
        STRLEN searchlen;
        const char* search = SvPVutf8(search_name, searchlen);
        instance_holder_t* instance_holder_p = svrv_to_ptr(aTHX_ self_sv);

        wasm_exporttype_t* export_type_p;

        wasm_extern_t* extern_p = _get_instance_export(
            instance_holder_p,
            search, searchlen,
            &export_type_p
        );

        wasm_externkind_t kind = wasm_extern_kind(extern_p);

        switch (kind) {
            case WASM_EXTERN_MEMORY:
            case WASM_EXTERN_GLOBAL:
            case WASM_EXTERN_FUNC: {
                export_to_sv_fp export_to_sv = get_export_to_sv_fp(kind);

                RETVAL = export_to_sv( aTHX_ self_sv, extern_p );
            } break;

            default: {
                const wasm_name_t* name = wasm_exporttype_name(export_type_p);

                const char* typename = get_externkind_description(wasm_extern_kind(extern_p));
                croak(
                    "%" SVf " doesn’t support export “%.*s”’s type (%s).",
                    self_sv,
                    (int) name->size, name->data,
                    typename
                );
            }
        }

    OUTPUT:
        RETVAL

# void
# export_memories (SV* self_sv)
#     PPCODE:
#         XSRETURN( xs_export_kind_list(aTHX_ SP, self_sv, WASM_EXTERN_MEMORY) );
# 
# void
# export_globals (SV* self_sv)
#     PPCODE:
#         XSRETURN( xs_export_kind_list(aTHX_ SP, self_sv, WASM_EXTERN_GLOBAL) );
# 
# void
# export_functions (SV* self_sv)
#     PPCODE:
#         XSRETURN( xs_export_kind_list(aTHX_ SP, self_sv, WASM_EXTERN_FUNC) );

void
call (SV* self_sv, SV* funcname_sv, ...)
    PPCODE:
        STRLEN funcname_len;
        const char* funcname = SvPVutf8(funcname_sv, funcname_len);

        unsigned given_args_count = items - 2;

        instance_holder_t* instance_holder_p = svrv_to_ptr(aTHX_ self_sv);

        wasm_exporttype_t* export_type = NULL;

        wasm_func_t* func = _get_instance_function(aTHX_ instance_holder_p, funcname, funcname_len, &export_type);

        if (!func) {
            croak("No function named “%" SVf "” exists!", funcname_sv);
        }

        _start_wasi_if_needed(aTHX_ instance_holder_p);

        unsigned retvals = _call_wasm( aTHX_ SP, func, &ST(2), given_args_count );

        XSRETURN(retvals);

void
DESTROY (SV* self_sv)
    CODE:
        destroy_instance_sv(aTHX_ self_sv);

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer       PACKAGE = Wasm::Wasmer::Extern

PROTOTYPES: DISABLE

void
DESTROY (SV* self_sv)
    CODE:
        destroy_extern_sv(aTHX_ self_sv);

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer       PACKAGE = Wasm::Wasmer::Global

PROTOTYPES: DISABLE

SV*
get (SV* self_sv)
    CODE:
        extern_holder_t* holder = svrv_to_ptr(aTHX_ self_sv);
        RETVAL = global_holder_get_sv(aTHX_ holder);

    OUTPUT:
        RETVAL

SV*
set (SV* self_sv, SV* newval)
    CODE:
        extern_holder_t* holder = svrv_to_ptr(aTHX_ self_sv);
        global_holder_set_sv(aTHX_ holder, newval);

        RETVAL = SvREFCNT_inc(self_sv);

    OUTPUT:
        RETVAL

SV*
mutability (SV* self_sv)
    CODE:
        RETVAL = global_sv_mutability_sv(aTHX_ self_sv);

    OUTPUT:
        RETVAL

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer       PACKAGE = Wasm::Wasmer::Memory

PROTOTYPES: DISABLE

SV*
set (SV* self_sv, SV* replacement_sv, SV* offset_sv=NULL)
    CODE:
        extern_holder_t* holder_p = svrv_to_ptr(aTHX_ self_sv);

        memory_set(holder_p, replacement_sv, offset_sv);

        RETVAL = SvREFCNT_inc(self_sv);

    OUTPUT:
        RETVAL

SV*
get (SV* self_sv, SV* offset_sv=NULL, SV* length_sv=NULL)
    CODE:
        if (GIMME_V == G_VOID) {
            croak("get() is useless in void context!");
        }

        extern_holder_t* holder_p = svrv_to_ptr(aTHX_ self_sv);

        RETVAL = memory_get(holder_p, offset_sv, length_sv);

    OUTPUT:
        RETVAL

SV*
grow (SV* self_sv, SV* delta_sv)
    CODE:
        extern_holder_t* holder_p = svrv_to_ptr(aTHX_ self_sv);

        memory_grow(holder_p, delta_sv);

        RETVAL = SvREFCNT_inc(self_sv);

    OUTPUT:
        RETVAL

void
limits (SV* self_sv)
    PPCODE:
        if (GIMME_V != G_ARRAY) croak("List context only!");

        extern_holder_t* holder_p = svrv_to_ptr(aTHX_ self_sv);

        wasm_limits_t limits = memory_limits(holder_p);

        EXTEND(SP, 2);
        mPUSHu(limits.min);
        mPUSHu(limits.max);

UV
data_size (SV* self_sv)
    CODE:
        RETVAL = memory_sv_data_size(aTHX_ self_sv);

    OUTPUT:
        RETVAL

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer       PACKAGE = Wasm::Wasmer::Function

PROTOTYPES: DISABLE

void
call (SV* self_sv, ...)
    PPCODE:
        extern_holder_t* holder_p = svrv_to_ptr(aTHX_ self_sv);

        wasm_func_t* func = wasm_extern_as_func( holder_p->extern_p );

        unsigned count = _call_wasm( aTHX_ SP, func, &ST(1), items - 1 );

        XSRETURN(count);

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer       PACKAGE = Wasm::Wasmer::WASI

SV*
_new (SV* classname_sv, SV* wasiname_sv, SV* opts_hr=NULL)
    CODE:
        const char* classname = SvPVbyte_nolen(classname_sv);
        const char* wasiname = SvPVutf8_nolen(wasiname_sv);

        wasi_config_t* config = wasi_config_new(wasiname);

        if (opts_hr && SvOK(opts_hr)) {
            HV* opts_hv = (HV*) SvRV(opts_hr);

            SV** args_arr = hv_fetchs(opts_hv, "args", 0);

            if (args_arr && *args_arr && SvOK(*args_arr)) {
                AV* args = (AV*) SvRV(*args_arr);

                SSize_t av_len = 1 + av_top_index(args);

                for (UV i=0; i<av_len; i++) {
                    SV *arg = *(av_fetch(args, i, 0));

                    wasi_config_arg(config, SvPVutf8_nolen(arg));
                }
            }

            SV** svr = hv_fetchs(opts_hv, "stdin", 0);
            if (svr && *svr && SvOK(*svr)) {
                const char* value = SvPVbyte_nolen(*svr);

                if (strEQ(value, "inherit")) {
                    wasi_config_inherit_stdin(config);
                }
                else {
                    assert(0);
                }
            }

            svr = hv_fetchs(opts_hv, "stdout", 0);
            if (svr && *svr && SvOK(*svr)) {
                const char* value = SvPVbyte_nolen(*svr);

                if (strEQ(value, "inherit")) {
                    wasi_config_inherit_stdout(config);
                }
                else if (strEQ(value, "capture")) {
                    wasi_config_capture_stdout(config);
                }
                else {
                    assert(0);
                }
            }

            svr = hv_fetchs(opts_hv, "stderr", 0);
            if (svr && *svr && SvOK(*svr)) {
                const char* value = SvPVbyte_nolen(*svr);

                if (strEQ(value, "inherit")) {
                    wasi_config_inherit_stderr(config);
                }
                else if (strEQ(value, "capture")) {
                    wasi_config_capture_stderr(config);
                }
                else {
                    assert(0);
                }
            }

            svr = hv_fetchs(opts_hv, "env", 0);
            if (svr && *svr && SvOK(*svr)) {
                AV* env = (AV*) SvRV(*svr);

                SSize_t av_len = 1 + av_top_index(env);

                for (UV i=0; i<av_len; i += 2) {
                    const char *key = SvPVutf8_nolen( *(av_fetch(env, i, 0) ) );
                    const char *value = SvPVutf8_nolen( *(av_fetch(env, 1 + i, 0) ) );

                    wasi_config_env(config, key, value);
                }
            }

            svr = hv_fetchs(opts_hv, "preopen_dirs", 0);
            if (svr && *svr && SvOK(*svr)) {
                AV* dirs = (AV*) SvRV(*svr);

                SSize_t av_len = 1 + av_top_index(dirs);

                for (UV i=0; i<av_len; i++) {
                    SV* dir = *(av_fetch(dirs, i, 0));
                    bool ok = wasi_config_preopen_dir(config, SvPVutf8_nolen(dir));
                    if (!ok) {
                        _wasi_config_delete(config);
                        _croak_if_wasmer_error("Failed to preopen directory %" SVf, dir);
                    }
                }
            }

            svr = hv_fetchs(opts_hv, "map_dirs", 0);
            if (svr && *svr && SvOK(*svr)) {
                HV* map = (HV*) SvRV(*svr);

                hv_iterinit(map);
                HE* h_entry;

                while ( (h_entry = hv_iternext(map)) ) {
                    SV* key = hv_iterkeysv(h_entry);
                    SV* value = hv_iterval(map, h_entry);

                    const char* keystr = SvPVutf8_nolen(key);
                    const char* valuestr = SvPVutf8_nolen(value);

                    bool ok = wasi_config_mapdir( config, keystr, valuestr );

                    if (!ok) {
                        _wasi_config_delete(config);
                        _croak_if_wasmer_error("Failed to map alias %s to directory %s", keystr, valuestr);
                    }
                }
            }
        }

        wasi_env_t* wasienv = wasi_env_new(config);

        wasi_holder_t* holder = wasi_env_to_holder(aTHX_ wasienv);

        RETVAL = ptr_to_svrv(aTHX_ holder, gv_stashpv(classname, FALSE));

    OUTPUT:
        RETVAL

SV*
read_stdout (SV* self_sv, SV* len_sv)
    CODE:
        UV len = grok_uv(aTHX_ len_sv);

        wasi_holder_t* holder = svrv_to_ptr(aTHX_ self_sv);

        RETVAL = wasi_holder_read_stdout(aTHX_ holder, len);

    OUTPUT:
        RETVAL

SV*
read_stderr (SV* self_sv, SV* len_sv)
    CODE:
        UV len = grok_uv(aTHX_ len_sv);

        wasi_holder_t* holder = svrv_to_ptr(aTHX_ self_sv);

        RETVAL = wasi_holder_read_stderr(aTHX_ holder, len);

    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        wasi_holder_t* holder = svrv_to_ptr(aTHX_ self_sv);

        warn_destruct_if_needed(self_sv, holder->pid);

        wasi_env_delete(holder->env);

        Safefree(holder);
