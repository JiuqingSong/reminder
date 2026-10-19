# 用法: perl gen.pl strings.tsv > Localizable.xcstrings
# TSV 每行：简体原文(key) \t 英文 \t 繁体。英文写成 one=...|other=... 时生成复数变体。
# 文本里的 \n 原样保留（在 JSON 里就是换行），双引号转义。
use utf8;
use open qw(:std :utf8);

sub esc { my $s = shift; $s =~ s/"/\\"/g; return $s; }

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
    my ($k, $en, $hant) = split /\t/;
    die "bad row: $_" unless defined $hant;
    push @rows, [$k, $en, $hant];
}
@rows = sort { $a->[0] cmp $b->[0] } @rows;

print qq({\n  "sourceLanguage" : "zh-Hans",\n  "strings" : {\n);
my @out;
for my $r (@rows) {
    my ($k, $en, $hant) = @$r;
    push @out, qq(    ") . esc($k) . qq(" : {\n      "localizations" : {\n        "en" : )
        . loc($en, "        ") . qq(,\n        "zh-Hant" : ) . loc($hant, "        ")
        . qq(\n      }\n    });
}
print join(",\n", @out);
print qq(\n  },\n  "version" : "1.0"\n}\n);
