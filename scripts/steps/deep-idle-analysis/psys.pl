#!/usr/bin/perl
use strict; use warnings; my $sec = shift // 10;
sub snap { my $o = `ioreg -l -d1 -w0 -r -k WhateverXeCpuStat 2>/dev/null`; $o =~ /"WhateverXeCpuStat" = <([0-9a-f]+)>/ or die "WhateverXeCpuStat 없음\n"; my @b = unpack("Q<*", pack("H*", $1)); return \@b; }
my $a = snap(); die "이 빌드에는 PSYS 항목이 없음\n" if @$a < 26;
die "PSYS 읽기 불가 (상태 $a->[25]: 1=안전한 읽기 함수 없음, 2=MSR 없음)\n" if $a->[25];
select(undef, undef, undef, $sec); my $b = snap();
my $dt = ($b->[1] - $a->[1]); my $eu = 1 / (2 ** (($b->[14] >> 8) & 0x1F));
my $tsc_hz = $dt / $sec;   # 근사(대기 시간 기준)
my $ps = (($b->[24] - $a->[24]) & 0xFFFFFFFF) * $eu / $sec; my $pk = (($b->[15] - $a->[15]) & 0xFFFFFFFF) * $eu / $sec;
printf "PSYS %.2fW  패키지 %.2fW  PC8 %.1f%%  (PSYS 원값 %d → %d)\n", $ps, $pk, 100 * ($b->[6] - $a->[6]) / $dt, $a->[24] & 0xFFFFFFFF, $b->[24] & 0xFFFFFFFF;
