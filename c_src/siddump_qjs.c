#include <stdlib.h>
#include <string.h>
#include "quickjs.h"
#include "siddump/siddump.h"

static JSValue js_native_siddump(JSContext *ctx, JSValueConst this_val,
                                 int argc, JSValueConst *argv)
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "Expected input SID filename");

    const char *filename = JS_ToCString(ctx, argv[0]);
    if (!filename)
        return JS_EXCEPTION;

    int seconds = 210;
    int subtune = 0;

    if (argc > 1 && !JS_IsUndefined(argv[1])) {
        if (JS_ToInt32(ctx, &seconds, argv[1])) {
            JS_FreeCString(ctx, filename);
            return JS_EXCEPTION;
        }
    }

    if (argc > 2 && !JS_IsUndefined(argv[2])) {
        if (JS_ToInt32(ctx, &subtune, argv[2])) {
            JS_FreeCString(ctx, filename);
            return JS_EXCEPTION;
        }
    }

    char *dump_text = siddump_emulate_to_string(filename, seconds, subtune);
    JS_FreeCString(ctx, filename);

    if (!dump_text) {
        return JS_ThrowInternalError(ctx, "Failed to emulate SID file");
    }

    JSValue ret = JS_NewString(ctx, dump_text);
    free(dump_text);
    return ret;
}

static const JSCFunctionListEntry js_siddump_funcs[] = {
    JS_CFUNC_DEF("emulateSid", 3, js_native_siddump),
};

static int js_siddump_init(JSContext *ctx, JSModuleDef *m)
{
    return JS_SetModuleExportList(ctx, m, js_siddump_funcs,
                                  sizeof(js_siddump_funcs) / sizeof(js_siddump_funcs[0]));
}

JSModuleDef *js_init_module_siddump_native(JSContext *ctx, const char *module_name)
{
    JSModuleDef *m;
    m = JS_NewCModule(ctx, module_name, js_siddump_init);
    if (!m)
        return NULL;
    JS_AddModuleExportList(ctx, m, js_siddump_funcs,
                           sizeof(js_siddump_funcs) / sizeof(js_siddump_funcs[0]));
    return m;
}
