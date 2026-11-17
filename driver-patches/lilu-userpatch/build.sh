#!/bin/bash
set -e
S="$(cd "$(dirname "$0")" && pwd)"; P="$S/Lilu"; O="$S/build"; LTO="${LTO--flto}"
rm -rf "$O"; mkdir -p "$O/obj"
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
VER=1.7.3
COMMON=(-target x86_64-apple-macos10.6 -isysroot "$SDK" -O3 -funroll-loops $LTO -fno-common -fno-builtin -mkernel -fapple-kext -fasm-blocks -fstrict-aliasing
  -fvisibility=hidden -nostdinc -I"$P/MacKernelSDK/Headers" -I"$P/capstone/include" -I"$P/lzvn" -I"$P/Lilu" -I"$P/sha256" -I"$P/hde" -I"$P/umm_malloc" -I"$P/capstone" -I"$P/Lilu/Headers" -I"$P/Lilu/PrivateHeaders" -I"$P/Lilu/Sources"
  -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT
  -DCAPSTONE_HAS_X86=1 -DCAPSTONE_HAS_OSXKERNEL=1 -DCAPSTONE_DIET=1 -DCAPSTONE_X86_REDUCE=1 -DCAPSTONE_STATIC=1
  -DUMM_BEST_FIT=1 -DUMM_MALLOC_CFG_HEAP_SIZE=0x10000 -DMODULE_VERSION=$VER -DPRODUCT_NAME=Lilu
  -mmmx -msse -msse2 -msse3 -mfpmath=sse -mssse3 -ftree-vectorize -fno-non-call-exceptions -fno-asynchronous-unwind-tables
  -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-register -Wno-unknown-pragmas -Wno-unknown-warning-option
  -Wno-ossharedptr-misuse -Wno-vla -Werror -nostdlib -Wno-stdlibcxx-not-found)
cat > "$O/Lilu_info.c" <<'EOT'
#include <mach/mach_types.h>
extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
__private_extern__ kern_return_t Lilu_kern_start(kmod_info_t *ki, void *data);
__private_extern__ kern_return_t Lilu_kern_stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(as.vit9696.Lilu, "1.7.3", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = Lilu_kern_start;
__private_extern__ kmod_stop_func_t *_antimain = Lilu_kern_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__ ;
EOT
objs=()
cc() { local src="$1"; shift; local o="$O/obj/$(basename "$src").o"; clang "$@" "${COMMON[@]}" -c "$src" -o "$o"; objs+=("$o"); }
for f in "$P"/Lilu/Sources/*.cpp; do cc "$f" -x c++ -std=c++1y -fno-rtti -fno-exceptions -fvisibility-inlines-hidden; done
for f in "$P"/Lilu/Sources/kern_ubsan.c "$P"/capstone/{cs,MCInst,MCInstrDesc,MCRegisterInfo,SStream,utils}.c "$P"/capstone/arch/X86/X86{ATTInstPrinter,Disassembler,DisassemblerDecoder,IntelInstPrinter,Mapping,Module}.c \
         "$P"/hde/hde32.c "$P"/hde/hde64.c "$P"/lzvn/lzvn.c "$P"/sha256/sha256.c "$P"/umm_malloc/umm_malloc.c "$O/Lilu_info.c"; do cc "$f" -x c -std=c11; done
cc "$P/Lilu/Sources/kern_efi_trampoline_x86_64.s" -x assembler-with-cpp
K="$O/Lilu.kext/Contents"; mkdir -p "$K/MacOS"
clang++ -target x86_64-apple-macos10.6 -isysroot "$SDK" -O3 $LTO -L"$P/MacKernelSDK/Library/x86_64" -dead_strip -static -nostdlib \
  -Xlinker -kext -Xlinker -export_dynamic -Xlinker -no_deduplicate "${objs[@]}" -lkmodc++ -lkmod -lcc_kext -o "$K/MacOS/Lilu"
cp "$K/MacOS/Lilu" "$O/Lilu.unstripped"
strip -x "$K/MacOS/Lilu"
sed -e 's/\$(EXECUTABLE_NAME)/Lilu/; s/\$(PRODUCT_BUNDLE_IDENTIFIER)/as.vit9696.Lilu/; s/\$(PRODUCT_NAME:rfc1034identifier)/Lilu/; s/\$(PRODUCT_NAME)/Lilu/; s/\$(MODULE_VERSION)/'$VER'/' "$P/Lilu/Info.plist" > "$K/Info.plist"
plutil -lint "$K/Info.plist"; file "$K/MacOS/Lilu"
