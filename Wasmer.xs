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

#define WASI_INSTANCE_CLASS "Wasm::Wasmer::WasiInstance"
#define MEMORY_CLASS "Wasm::Wasmer::Memory"
#define FUNCTION_CLASS "Wasm::Wasmer::Function"

#define _ptr_to_svrv ptr_to_svrv

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

        RETVAL = create_engine_sv(aTHX_ class_sv);

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
        RETVAL = create_instance_sv(aTHX_ NULL, self_sv, imports_sv);

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
    store_holder_t* store_holder_p = svrv_to_ptr(aTHX_ store_sv);

        wasm_trap_t* traps = NULL;

    wasi_config_t* config = wasi_config_new("");

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
        instance_holder_p->pid      = getpid();
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

        instance_holder_t* instance_holder_p = _get_instance_holder_p_from_sv(aTHX_ self_sv);

        module_holder_t* module_holder_p = _get_module_holder_p_from_sv(aTHX_ instance_holder_p->module_sv);

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

