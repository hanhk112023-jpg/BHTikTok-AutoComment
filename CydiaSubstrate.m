#import <Foundation/Foundation.h>
#import <objc/runtime.h>

__attribute__((visibility("default")))
void MSHookMessageEx(Class _class, SEL sel, IMP imp, IMP *result) {
    if (!_class || !sel || !imp) {
        if (result) *result = NULL;
        return;
    }
    Method method = class_getInstanceMethod(_class, sel);
    if (!method) {
        const char *type = "v@:";
        class_addMethod(_class, sel, imp, type);
        if (result) *result = NULL;
        return;
    }
    IMP oldImp = method_setImplementation(method, imp);
    if (result) *result = oldImp;
}
