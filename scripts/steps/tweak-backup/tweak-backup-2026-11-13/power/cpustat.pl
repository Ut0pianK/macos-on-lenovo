#!/usr/bin/perl
use strict; use warnings;
my $sec = shift // 10;
sub snap { my $o = `ioreg -l -d1 -w0 -r -k WhateverXeCpuStat 2>/dev/null`; $o =~ /"WhateverXeCpuStat" = <([0-9a-f]+)>/ or die "WhateverXeCpuStat 없음 (-wex-cpustat 부팅인지 확인)\n";
  my @b = unpack("Q<*", pack("H*", $1)); return \@b; }
my $a = snap(); sleep $sec; my $b = snap();
my $dt = $b->[1] - $a->[1];
my @n = ("PC2","PC3","PC6","PC7","PC8","PC9","PC10");
print "TSC 간격: $dt ($sec 초)\n";
for my $i (0..6) { my $d = $b->[2+$i] - $a->[2+$i]; printf "  %-4s %6.2f %%\n", $n[$i], 100*$d/$dt; }
my $e2 = $b->[9]; printf "PKG_CST_CONFIG_CONTROL 0xE2 = 0x%x  (패키지 C-state 한계 코드 %d, 잠금 %s)\n", $e2, $e2 & 0xF, ($e2>>15)&1 ? "예":"아니오";
printf "EPB(0x1B0) = %d  (0=성능 … 15=절전)\n", $b->[10] & 0xF;
if ($b->[23]) {
  my $r = $b->[13]; printf "HWP: PM_ENABLE=%d  REQUEST min=%d max=%d desired=%d EPP=0x%02x (0x00=성능 … 0xFF=절전)\n", $b->[11]&1, $r&0xFF, ($r>>8)&0xFF, ($r>>16)&0xFF, ($r>>24)&0xFF;
  my $c = $b->[12]; printf "HWP_CAP: highest=%d guaranteed=%d efficient=%d lowest=%d\n", $c&0xFF, ($c>>8)&0xFF, ($c>>16)&0xFF, ($c>>24)&0xFF;
}
my $eu = 1 / (2 ** (($b->[14] >> 8) & 0x1F)); my $s = $dt; 
my $secs = $sec;
for ([15,"패키지"],[16,"코어(PP0)"],[17,"그래픽(PP1)"]) { my ($i,$nm)=@$_; my $d = ($b->[$i] - $a->[$i]) & 0xFFFFFFFF; printf "%-10s %5.2f W\n", $nm, $d*$eu/$secs; }
printf "현재 배수 PERF_STATUS = %d (x100MHz), 이 코어 C6/C7 증가 %d/%d\n", ($b->[20]>>8)&0xFF, $b->[18]-$a->[18], $b->[19]-$a->[19];
printf "MISC_ENABLE 0x1A0 = 0x%x (터보 꺼짐 bit38=%d, EIST bit16=%d)\n", $b->[22], ($b->[22]>>38)&1, ($b->[22]>>16)&1;
