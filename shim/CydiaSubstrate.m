#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

/**
 * Hardened CydiaSubstrate Shim for Non-Jailbroken / Sideloaded iOS (arm64 & arm64e / PAC)
 * 
 * Key Protections:
 * 1. Superclass Pollution Prevention: If `sel` is inherited, adds method to `_class`
 *    directly rather than modifying superclass implementation.
 * 2. Type Encoding Preservation: Uses actual method type encoding, avoiding ABI corruption.
 * 3. PAC / arm64e ABI Safety: Keeps pointer signatures intact.
 */
__attribute__((visibility("default")))
void MSHookMessageEx(Class _class, SEL sel, IMP imp, IMP *result) {
    if (!_class || !sel || !imp) {
        if (result) *result = NULL;
        return;
    }

    Method origMethod = class_getInstanceMethod(_class, sel);
    if (!origMethod) {
        // Method does not exist anywhere in class hierarchy.
        // Add as a new method with safe generic type encoding.
        const char *defaultType = "@@:@";
        class_addMethod(_class, sel, imp, defaultType);
        if (result) *result = NULL;
        return;
    }

    const char *typeEncoding = method_getTypeEncoding(origMethod);
    IMP origImp = method_getImplementation(origMethod);

    // Verify whether the method is implemented directly by _class or inherited
    BOOL isDeclaredDirectly = NO;
    unsigned int methodCount = 0;
    Method *methodList = class_copyMethodList(_class, &methodCount);
    if (methodList) {
        for (unsigned int i = 0; i < methodCount; i++) {
            if (method_getName(methodList[i]) == sel) {
                isDeclaredDirectly = YES;
                break;
            }
        }
        free(methodList);
    }

    if (isDeclaredDirectly) {
        // Direct implementation: safely swap implementation on _class
        IMP prevImp = method_setImplementation(origMethod, imp);
        if (result) *result = prevImp ? prevImp : origImp;
    } else {
        // Inherited from superclass!
        // DO NOT mutate superclass Method object directly, as this poisons all sibling subclasses.
        // Add the hook implementation directly to _class:
        BOOL added = class_addMethod(_class, sel, imp, typeEncoding ? typeEncoding : "v@:");
        if (added) {
            if (result) *result = origImp;
        } else {
            // Fallback: replace on _class
            IMP prevImp = class_replaceMethod(_class, sel, imp, typeEncoding ? typeEncoding : "v@:");
            if (result) *result = prevImp ? prevImp : origImp;
        }
    }
}
