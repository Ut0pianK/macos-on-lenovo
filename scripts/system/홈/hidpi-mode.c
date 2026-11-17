
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
typedef struct { uint32_t modeNumber, flags, width, height, depth; uint8_t unk[170]; uint16_t freq; uint8_t more[16]; float density; } Mode;
extern void CGSGetNumberOfDisplayModes(CGDirectDisplayID, int*);
extern void CGSGetDisplayModeDescriptionOfLength(CGDirectDisplayID, int, Mode*, int);
extern void CGSGetCurrentDisplayMode(CGDirectDisplayID, int*);
extern CGError CGSConfigureDisplayMode(CGDisplayConfigRef, CGDirectDisplayID, int);
int main(int argc,char**argv){
  CGDirectDisplayID d=CGMainDisplayID(); int n=0,cur=-1; CGSGetNumberOfDisplayModes(d,&n); CGSGetCurrentDisplayMode(d,&cur);
  if(argc<3){
    for(int i=0;i<n;i++){ Mode m; memset(&m,0,sizeof m); CGSGetDisplayModeDescriptionOfLength(d,i,&m,sizeof m);
      if(m.depth!=8) continue;
      printf("%4u x %-4u %s%s\n",m.width,m.height,m.density>1.5?"HiDPI":"     ",i==cur?"  <- current":""); }
    return 0; }
  uint32_t w=atoi(argv[1]),h=atoi(argv[2]); int want2x=1,test=0,secs=6;
  for(int a=3;a<argc;a++){ if(!strcmp(argv[a],"1x")) want2x=0; else if(!strcmp(argv[a],"test")){ test=1; if(a+1<argc) secs=atoi(argv[a+1]); } }
  int pick=-1;
  for(int i=0;i<n;i++){ Mode m; memset(&m,0,sizeof m); CGSGetDisplayModeDescriptionOfLength(d,i,&m,sizeof m);
    if(m.width==w&&m.height==h&&m.depth==8&&((m.density>1.5)==want2x)) pick=i; }
  if(pick<0){ fprintf(stderr,"no such mode: %ux%u %s\n",w,h,want2x?"HiDPI":"1x"); return 1; }
  if(pick==cur){ printf("already in mode %d\n",pick); return 0; }
  CGDisplayConfigRef c; CGError e=CGBeginDisplayConfiguration(&c); if(e){ fprintf(stderr,"begin failed %d\n",e); return 2; }
  e=CGSConfigureDisplayMode(c,d,pick); if(e){ CGCancelDisplayConfiguration(c); fprintf(stderr,"configure failed %d\n",e); return 3; }
  e=CGCompleteDisplayConfiguration(c,test?kCGConfigureForAppOnly:kCGConfigurePermanently);
  if(e){ fprintf(stderr,"complete failed %d\n",e); return 4; }
  int now=-1; CGSGetCurrentDisplayMode(d,&now);
  printf("switched to mode %d (%ux%u %s)%s, current=%d, pixels=%zux%zu\n",pick,w,h,want2x?"HiDPI":"1x",test?" [test]":"",now,CGDisplayPixelsWide(d),CGDisplayPixelsHigh(d));
  if(test){ fflush(stdout); sleep(secs); CGRestorePermanentDisplayConfiguration(); puts("reverted"); }
  return 0; }
