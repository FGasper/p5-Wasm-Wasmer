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

#include "p5_wasm_wasmer.h"
#include "wasmer_engine.xsc"
#include "wasmer_store.xsc"
#include "wasmer_module.xsc"
#include "wasmer_instance.xsc"
#include "wasmer_function.xsc"
#include "wasmer_memory.xsc"
#include "wasmer_wasi.xsc"

#define WASI_CLASS "Wasm::Wasmer::WASI"
#define MEMORY_CLASS "Wasm::Wasmer::Memory"
#define FUNCTION_CLASS "Wasm::Wasmer::Function"

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
                wasm_param[i].of.i32 = grok_i32( given_arg[i] );
                break;

            case WASM_I64:
                wasm_param[i].of.i64 = grok_i64( given_arg[i] );
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

    _croak_if_trap(aTHX_ trap);

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
                    mPUSHs( newSVnv( (float) wasm_result[i].of.f32 ) );
                    break;

                case WASM_F64:
                    mPUSHs( newSVnv( (float) wasm_result[i].of.f64 ) );
                    break;

                default:
                    croak("Function return #%d is of unknown type!", 1 + i);
            }
        }

    }

    return results_count;
}

static inline void _start_wasi_if_needed(pTHX_ instance_holder_t* instance_holder_p) {
    if (!instance_holder_p->wasi_sv) return;

    if (instance_holder_p->wasi_started) return;

    instance_holder_p->wasi_started = true;

    wasm_func_t* func = wasi_get_start_function(instance_holder_p->instance);

    wasm_val_t args_val[0] = {};
    wasm_val_t results_val[0] = {};
    wasm_val_vec_t args = WASM_ARRAY_VEC(args_val);
    wasm_val_vec_t results = WASM_ARRAY_VEC(results_val);

    own wasm_trap_t* trap = wasm_func_call(func, &args, &results);

    _croak_if_trap(aTHX_ trap);
}

/* ---------------------------------------------------------------------- */

MODULE = Wasm::Wasmer     PACKAGE = Wasm::Wasmer

BOOT:
    newCONSTSUB(gv_stashpv("Wasm::Wasmer", 0), "WASM_EXTERN_FUNC", newSVuv(WASM_EXTERN_FUNC));

# void
# check_leaks (SV* wasm_sv)
#     CODE:
#         wasm_engine_t* engine = wasm_engine_new();
#         wasm_store_t* store = wasm_store_new(engine);
#
#         STRLEN wasmlen;
#         const char* wasm = SvPVbyte(wasm_sv, wasmlen);
#
#         wasm_byte_vec_t binary;
#         wasm_byte_vec_new(&binary, wasmlen, wasm);
#
#         wasm_module_t* module = wasm_module_new(store, &binary);
#         wasm_module_delete(module);
#
#         wasm_byte_vec_delete(&binary);
#         wasm_store_delete(store);
#         wasm_engine_delete(engine);

SV*
wat2wasm ( SV* wat_sv )
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
new (SV* class_sv, ...)
    CODE:
        if (!SvPOK(class_sv)) croak("Give a class name!");

        RETVAL = create_engine_sv(aTHX_ class_sv, &ST(1), items - 1);

    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        destroy_engine_sv(aTHX_ self_sv);

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer     PACKAGE = Wasm::Wasmer::Store

PROTOTYPES: DISABLE

SV*
new (SV* class_sv, SV* engine_sv=NULL)
    CODE:
        croak_if_non_null_not_derived(aTHX_ engine_sv, P5_WASM_WASMER_ENGINE_CLASS);

        if (!SvPOK(class_sv)) croak("Give a class name!");

        RETVAL = create_store_sv(aTHX_ class_sv, engine_sv);

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
        if (store_sv) {
            SvREFCNT_inc(store_sv);
        }
        else {
            store_sv = create_store_sv(aTHX_ NULL, NULL);
        }

        store_holder_t* store_holder_p = svrv_to_ptr(aTHX_ store_sv);

        STRLEN byteslen;
        const char* bytes = SvPVbyte(bytes_sv, byteslen);

        wasm_byte_vec_t vector;
        wasm_byte_vec_new(&vector, byteslen, (wasm_byte_t*) bytes);

        wasm_module_t* module = wasm_module_deserialize( store_holder_p->store, &vector );

        wasm_byte_vec_delete(&vector);

        if (!module) croak("Failed to deserialize module!");

        RETVAL = module_to_sv(aTHX_ module, store_sv, P5_WASM_WASMER_MODULE_CLASS);

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

void
export_memories (SV* self_sv)
    PPCODE:
        if (GIMME_V != G_ARRAY) croak("List context only!");

        instance_holder_t* instance_holder_p = svrv_to_ptr(aTHX_ self_sv);

        wasm_extern_vec_t* exports = &instance_holder_p->exports;

        module_holder_t* module_holder_p = svrv_to_ptr(aTHX_ instance_holder_p->module_sv);

        wasm_exporttype_vec_t* export_types = &module_holder_p->export_types;

        unsigned return_count = 0;

        SV* possible_memory_sv[exports->size];

        pid_t pid = getpid();

        for (unsigned i = 0; i<exports->size; i++) {
            if (wasm_extern_kind(exports->data[i]) != WASM_EXTERN_MEMORY)
                continue;

            memory_holder_t* memory_holder;
            Newx(memory_holder, 1, memory_holder_t);

            wasm_memory_t* memory = wasm_extern_as_memory(exports->data[i]);

            memory_holder->memory = memory;
            memory_holder->pid = pid;
            memory_holder->export_type = export_types->data[i];

            memory_holder->instance_sv = self_sv;
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

        instance_holder_t* instance_holder_p = svrv_to_ptr(aTHX_ self_sv);

        module_holder_t* module_holder_p = svrv_to_ptr(aTHX_ instance_holder_p->module_sv);

        wasm_exporttype_vec_t* export_types = &module_holder_p->export_types;

        wasm_extern_vec_t* exports = &instance_holder_p->exports;

        unsigned return_count = 0;

        SV* possible_function_sv[exports->size];

        pid_t pid = getpid();

        for (unsigned i = 0; i<exports->size; i++) {
            if (wasm_extern_kind(exports->data[i]) != WASM_EXTERN_FUNC)
                continue;

            function_holder_t* function_holder;
            Newx(function_holder, 1, function_holder_t);

            wasm_func_t* function = wasm_extern_as_func(exports->data[i]);

            function_holder->function = function;
            function_holder->pid = pid;
            function_holder->export_type = export_types->data[i];

            function_holder->instance_sv = self_sv;
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

        instance_holder_t* instance_holder_p = svrv_to_ptr(aTHX_ self_sv);

        wasm_exporttype_t* export_type;

        wasm_func_t* func = _get_instance_function(aTHX_ instance_holder_p, funcname, funcname_len, &export_type);

        if (func) {
            _start_wasi_if_needed(aTHX_ instance_holder_p);

            unsigned retvals = _call_wasm( aTHX_ SP, func, export_type, &ST(2), given_args_count );

            XSRETURN(retvals);
        }

        croak("No function named “%" SVf "” exists!", funcname_sv);

void
DESTROY (SV* self_sv)
    CODE:
        destroy_instance_sv(aTHX_ self_sv);

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer       PACKAGE = Wasm::Wasmer::Memory

SV*
name (SV* self_sv)
    CODE:
        RETVAL = memory_sv_name_sv(aTHX_ self_sv);

    OUTPUT:
        RETVAL

UV
data (SV* self_sv)
    CODE:
        RETVAL = memory_sv_data_uv(aTHX_ self_sv);

    OUTPUT:
        RETVAL

IV
data_size (SV* self_sv)
    CODE:
        RETVAL = memory_sv_data_size_iv(aTHX_ self_sv);

    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        destroy_memory_sv(aTHX_ self_sv);

# ----------------------------------------------------------------------

MODULE = Wasm::Wasmer       PACKAGE = Wasm::Wasmer::Function

void
DESTROY (SV* self_sv)
    CODE:
        destroy_function_sv(aTHX_ self_sv);

SV*
name (SV* self_sv)
    CODE:
        RETVAL = function_sv_name_sv(aTHX_ self_sv);

    OUTPUT:
        RETVAL

void
call (SV* self_sv, ...)
    PPCODE:
        function_holder_t* function_holder_p = svrv_to_ptr(aTHX_ self_sv);

        instance_holder_t* instance_holder_p = svrv_to_ptr(aTHX_ function_holder_p->instance_sv);

        _start_wasi_if_needed(aTHX_ instance_holder_p);

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

MODULE = Wasm::Wasmer       PACKAGE = Wasm::Wasmer::WASI

SV*
_new (SV* classname_sv, SV* wasiname_sv, SV* opts_hr=NULL)
    CODE:
        const char* classname = SvPVbyte_nolen(classname_sv);
        const char* wasiname = SvPVbyte_nolen(wasiname_sv);

        wasi_config_t* config = wasi_config_new(wasiname);

        if (opts_hr && SvOK(opts_hr)) {
            HV* opts_hv = (HV*) SvRV(opts_hr);

            SV** args_arr = hv_fetchs(opts_hv, "args", 0);

            if (args_arr && *args_arr && SvOK(*args_arr)) {
                AV* args = (AV*) SvRV(*args_arr);

                SSize_t av_len = 1 + av_top_index(args);

                for (UV i=0; i<av_len; i++) {
                    SV *arg = *(av_fetch(args, i, 0));

                    wasi_config_arg(config, SvPVbyte_nolen(arg));
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
                    const char *key = SvPVbyte_nolen( *(av_fetch(env, i, 0) ) );
                    const char *value = SvPVbyte_nolen( *(av_fetch(env, 1 + i, 0) ) );

                    wasi_config_env(config, key, value);
                }
            }

            svr = hv_fetchs(opts_hv, "preopen_dirs", 0);
            if (svr && *svr && SvOK(*svr)) {
                AV* dirs = (AV*) SvRV(*svr);

                SSize_t av_len = 1 + av_top_index(dirs);

                for (UV i=0; i<av_len; i++) {
                    SV *dir = *(av_fetch(dirs, i, 0));
                    wasi_config_preopen_dir(config, SvPVbyte_nolen(dir));
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

                    wasi_config_mapdir(
                        config,
                        SvPVbyte_nolen(key),
                        SvPVbyte_nolen(value)
                    );
                }
            }
        }

        wasi_env_t* wasienv = wasi_env_new(config);

        wasi_holder_t* holder = wasi_env_to_holder(aTHX_ wasienv);

        RETVAL = ptr_to_svrv(aTHX_ holder, gv_stashpv(classname, FALSE));

    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        wasi_holder_t* holder = svrv_to_ptr(aTHX_ self_sv);

        warn_destruct_if_needed(self_sv, holder->pid);

        wasi_env_delete(holder->env);

        Safefree(holder);
