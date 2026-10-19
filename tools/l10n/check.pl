# 用法: perl check.pl strings.tsv file.swift...
# 列出代码里有中文、但翻译表里没有的字符串，以及翻译表里多余的条目
use utf8;
use open qw(:std :utf8);
my $tsv = shift;
my %keys;
open my $t, '<', $tsv or die;
while (<$t>) {
    chomp;
    my ($k) = split /\t/;
    my $n = $k;
    $n =~ s/%(\d\$)?(lld|@|lf)/※/g;
    $n =~ s/\\n/\n/g;
    $keys{$n} = $k;
}
my %seen;
for my $f (@ARGV) {
    open my $h, '<', $f or die;
    my $ln = 0;
    while (my $line = <$h>) {
        $ln++;
        next if $line =~ /^\s*\/\//;
        $line =~ s/\s\/\/\s.*$//;
        while ($line =~ /"((?:[^"\\]|\\.)*)"/g) {
            my $s = $1;
            next unless $s =~ /\p{Han}/;
            1 while $s =~ s/\\\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)/※/;
            $s =~ s/\\"/"/g;
            $s =~ s/\\n/\n/g;
            $seen{$s} = 1;
            print "MISSING $f:$ln: $s\n" unless exists $keys{$s};
        }
    }
}
for my $n (sort keys %keys) { print "UNUSED: $keys{$n}\n" unless $seen{$n}; }
