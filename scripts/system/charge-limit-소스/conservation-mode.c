
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IdeaVPC"));
    if (!svc) { fprintf(stderr, "IdeaVPC not found\n"); return 2; }
    int rc = 0;
    if (argc > 1 && (!strcmp(argv[1], "on") || !strcmp(argv[1], "off"))) {
        CFBooleanRef v = !strcmp(argv[1], "on") ? kCFBooleanTrue : kCFBooleanFalse;
        kern_return_t kr = IORegistryEntrySetCFProperty(svc, CFSTR("ConservationMode"), v);
        if (kr != KERN_SUCCESS) { fprintf(stderr, "set failed: 0x%x\n", kr); rc = 1; }
    } else if (argc > 1 && strcmp(argv[1], "status")) {
        fprintf(stderr, "usage: conservation-mode [on|off|status]\n");
        IOObjectRelease(svc);
        return 64;
    }
    CFTypeRef cur = IORegistryEntryCreateCFProperty(svc, CFSTR("ConservationMode"), kCFAllocatorDefault, 0);
    if (cur && CFGetTypeID(cur) == CFBooleanGetTypeID())
        printf("%s\n", CFBooleanGetValue(cur) ? "on" : "off");
    else { printf("unknown\n"); if (!rc) rc = 3; }
    if (cur) CFRelease(cur);
    IOObjectRelease(svc);
    return rc;
}
