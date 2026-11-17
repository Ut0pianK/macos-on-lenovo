
#include <objc/runtime.h>
#include <objc/message.h>
#include <CoreGraphics/CGGeometry.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <mach-o/dyld.h>
static const void *kKey = &kKey;
static int solariumState = -1;
#define MSG(ret, ...) ((ret(*)(id, SEL, ##__VA_ARGS__))objc_msgSend)
static SEL S(const char *n) { return sel_registerName(n); }
static void ensureBacking(id g) {
    if (solariumState < 0) { int (*sol)(void) = (int(*)(void))dlsym(RTLD_DEFAULT, "NSSolariumEnabled"); solariumState = sol ? (sol() ? 1 : 0) : 1; }
    if (solariumState) return;
    if (!MSG(id)(g, S("window"))) return;
    CGRect b = ((CGRect(*)(id, SEL))objc_msgSend_stret)(g, S("bounds"));
    id v = objc_getAssociatedObject(g, kKey);
    if (!v) {
        Class VEV = objc_getClass("NSVisualEffectView"); if (!VEV) return;
        v = MSG(id, CGRect)(MSG(id)((id)VEV, S("alloc")), S("initWithFrame:"), b);
        MSG(void, long)(v, S("setMaterial:"), 5);
        MSG(void, long)(v, S("setBlendingMode:"), 0);
        MSG(void, long)(v, S("setState:"), 1);
        MSG(void, unsigned long)(v, S("setAutoresizingMask:"), 2 | 16);
        MSG(void, BOOL)(v, S("setWantsLayer:"), YES);
        objc_setAssociatedObject(g, kKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        MSG(void)(v, S("release"));
    }
    if (MSG(id)(v, S("superview")) != g) MSG(void, id, long, id)(g, S("addSubview:positioned:relativeTo:"), v, -1, nil);
    MSG(void, CGRect)(v, S("setFrame:"), b);
    double r = 0;
    if (class_getInstanceMethod(object_getClass(g), S("cornerRadius"))) r = MSG(double)(g, S("cornerRadius"));
    id layer = MSG(id)(v, S("layer"));
    if (layer) { MSG(void, double)(layer, S("setCornerRadius:"), r); MSG(void, BOOL)(layer, S("setMasksToBounds:"), r > 0); }
}
static void hook(Class c, SEL s) {
    Method m = class_getInstanceMethod(c, s); if (!m) return;
    IMP orig = method_getImplementation(m);
    IMP n = imp_implementationWithBlock(^(id self) { ((void(*)(id, SEL))orig)(self, s); ensureBacking(self); });
    if (!class_addMethod(c, s, n, method_getTypeEncoding(m))) method_setImplementation(m, n);
}
static int done;
static void tryInstall(void) {
    if (done) return;
    Class ge = objc_getClass("NSGlassEffectView"), gv = objc_getClass("NSGlassView");
    if (!ge && !gv) return;
    done = 1;
    Class cs[2] = { ge, gv };
    for (int i = 0; i < 2; i++) if (cs[i]) { hook(cs[i], S("viewDidMoveToWindow")); hook(cs[i], S("layout")); }
}

static int isSafari, safariDone;
static int solariumOff(void) {
    if (solariumState < 0) { int (*sol)(void) = (int(*)(void))dlsym(RTLD_DEFAULT, "NSSolariumEnabled"); if (!sol) return 0; solariumState = sol() ? 1 : 0; }
    return solariumState == 0;
}
static void trySafari(void) {
    if (!isSafari || safariDone) return;
    const char *names[2] = { "CompletionListWindow", "AutoFillCompletionWindow" };
    SEL s = S("shouldUseGlassBackdropView");
    if (!objc_getClass("RoundedWindow")) return;
    for (int i = 0; i < 2; i++) {
        Class c = objc_getClass(names[i]); if (!c) continue;
        Method m = class_getClassMethod(c, s); if (!m) continue;
        IMP orig = method_getImplementation(m);
        IMP n = imp_implementationWithBlock(^BOOL(id self) { return solariumOff() ? NO : ((BOOL(*)(id, SEL))orig)(self, s); });
        class_replaceMethod(object_getClass((id)c), s, n, method_getTypeEncoding(m));
    }
    safariDone = 1;
}
static void added(const struct mach_header *mh, intptr_t sl) { tryInstall(); trySafari(); }
__attribute__((constructor)) static void init(void) {
    isSafari = !strcmp(getprogname(), "Safari");
    tryInstall(); trySafari();
    if (!done || (isSafari && !safariDone)) _dyld_register_func_for_add_image(added);
}
