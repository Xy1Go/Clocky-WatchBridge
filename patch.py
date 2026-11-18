#!/usr/bin/env python3
# Clocky 启动加固补丁：
# 1) 给 NTKFaceDescriptor::isAvailableForDevice::swizzle() 加 NULL 保护（原代码在 Release 下 assert 被禁用，method 为 NULL 会段错误）
# 2) 用 @try/@catch 包住 +load 里的 swizzle，避免私有 API 异常导致启动闪退
import sys, os

repo = sys.argv[1]

def norm(s):
    return s.replace("\r\n", "\n")

# ---- 1) Swizzler.mm ----
swizzler_path = os.path.join(repo, "Clocky", "Swizzler.mm")
with open(swizzler_path, "rb") as f:
    s = f.read().decode("utf-8")
s = norm(s)

old_swizzle = """                assert(method != NULL);
                original = reinterpret_cast<decltype(original)>(method_getImplementation(method));
                method_setImplementation(method, reinterpret_cast<IMP>(custom));"""

new_swizzle = """                if (method != NULL) {
                    original = reinterpret_cast<decltype(original)>(method_getImplementation(method));
                    method_setImplementation(method, reinterpret_cast<IMP>(custom));
                }"""

if old_swizzle in s:
    s = s.replace(old_swizzle, new_swizzle)
    with open(swizzler_path, "wb") as f:
        f.write(s.encode("utf-8"))
    print("patched Swizzler.mm (NULL guard)")
else:
    print("WARNING: Swizzler.mm pattern not found, skip")

# ---- 2) AppDelegate.mm ----
appdel_path = os.path.join(repo, "Clocky", "AppDelegate.mm")
with open(appdel_path, "rb") as f:
    a = f.read().decode("utf-8")
a = norm(a)

old_load = """+ (void)load {
    swizzler::NTKFaceDescriptor::isAvailableForDevice::swizzle();
    swizzler::NTKFace::isRestrictedForDevice::swizzle();
}"""

new_load = """+ (void)load {
    @try {
        swizzler::NTKFaceDescriptor::isAvailableForDevice::swizzle();
        swizzler::NTKFace::isRestrictedForDevice::swizzle();
    } @catch (NSException *exception) {
        // 忽略启动时的私有 API 异常，避免闪退
    }
}"""

if old_load in a:
    a = a.replace(old_load, new_load)
    with open(appdel_path, "wb") as f:
        f.write(a.encode("utf-8"))
    print("patched AppDelegate.mm (@try/@catch)")
else:
    print("WARNING: AppDelegate.mm pattern not found, skip")
