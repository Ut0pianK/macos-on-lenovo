use Math::BigInt; my $o=`ioreg -rn AppleSmartBattery -w0`;
my ($a)=$o=~/"InstantAmperage" = (\d+)/; my ($b)=$o=~/"Amperage" = (\d+)/; my ($v)=$o=~/"Voltage" = (\d+)/; my ($t)=$o=~/"UpdateTime" = (\d+)/;
my ($tte)=$o=~/"AvgTimeToEmpty" = (\d+)/;
sub sg{my $x=Math::BigInt->new(shift); $x->bsub(Math::BigInt->new(2)->bpow(64)) if $x->bcmp(Math::BigInt->new(2)->bpow(63))>0; return $x->numify}
printf "t=%d inst=%.2fW avg=%.2fW tte=%s\n", $t%1000, -sg($a)*$v/1e6, -sg($b)*$v/1e6, $tte//'?';
