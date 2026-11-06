# 用法: perl gen.pl strings.tsv > Localizable.xcstrings
# TSV 每行：简体原文(key) \t 英文 \t 繁体 \t 日语 \t 韩语 \t 西班牙语（列顺序见 @langs）。
# 某列写成 one=...|other=... 时生成复数变体（英文、西班牙语需要；日语、韩语、中文不分单复数）。
# 文本里的 \n 原样保留（在 JSON 里就是换行），双引号转义。
# 行尾空格容易被编辑器删掉，要保留的空格写成 \s。
use utf8;
use open qw(:std :utf8);

my @langs = qw(en zh-Hant ja ko es);

sub esc { my $s = shift; $s =~ s/"/\\"/g; $s =~ s/\\s/ /g; return $s; }

sub unit {
    my ($v, $indent) = @_;
    return qq({\n$indent  "stringUnit" : {\n$indent    "state" : "translated",\n$indent    "value" : ") . esc($v) . qq("\n$indent  }\n$indent});
}

sub loc {
    my ($v, $indent) = @_;
    if ($v =~ /^one=(.*)\|other=(.*)$/) {
        my ($one, $other) = ($1, $2);
        return qq({\n$indent  "variations" : {\n$indent    "plural" : {\n$indent      "one" : )
            . unit($one, "$indent      ") . qq(,\n$indent      "other" : )
            . unit($other, "$indent      ") . qq(\n$indent    }\n$indent  }\n$indent});
    }
    return unit($v, $indent);
}

my @rows;
while (<>) {
    chomp;
    s/\r$//;
    next if /^\s*$/;
    my ($k, @vals) = split /\t/, $_, -1;
    die "bad row (need " . (@langs + 1) . " columns): $_" unless @vals == @langs;
    my %v;
    @v{@langs} = @vals;
    push @rows, [$k, \%v];
}
@rows = sort { $a->[0] cmp $b->[0] } @rows;

print qq({\n  "sourceLanguage" : "zh-Hans",\n  "strings" : {\n);
my @out;
for my $r (@rows) {
    my ($k, $v) = @$r;
    my @locs = map { qq(        "$_" : ) . loc($v->{$_}, "        ") } sort @langs;
    push @out, qq(    ") . esc($k) . qq(" : {\n      "localizations" : {\n)
        . join(",\n", @locs) . qq(\n      }\n    });
}
print join(",\n", @out);
print qq(\n  },\n  "version" : "1.0"\n}\n);
