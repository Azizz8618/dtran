#!/usr/bin/env perl
use utf8;
use feature 'unicode_strings';
use open ':encoding(UTF-8)';
use open ':std', ':encoding(UTF-8)';
use File::Temp qw(tempdir);
use Getopt::Long;

# verify_dtran.pl — поразрядная (побайтовая) сверка дизассемблированной
# программы с эталоном. Алгоритм по аналогии с verify.pl из re-dispak.
#
# 1. Дамп эталона с диска N1 через besmtool dump -> файл G*
# 2. Дамп проверяемого образа с диска N2 -> файл S*
# 3. cmp -l G* S* -> число различий + первое расхождение
# 4. Преобразование байтового смещения в зону/слово БЭСМ-6

my $gold_disk = '';
my $silver_disk = '';
my $gold_file = '';
my $silver_file = '';
my $zone = '';
my $length = 1;
my $sector = -1;
my $verbose = 0;
my $keep_files = 0;

GetOptions(
    'gold=s'       => \$gold_disk,
    'silver=s'     => \$silver_disk,
    'gold-file=s'  => \$gold_file,
    'silver-file=s'=> \$silver_file,
    'zone|z=s'     => \$zone,
    'length|l=i'   => \$length,
    'sector=i'     => \$sector,
    'verbose|v'    => \$verbose,
    'keep'         => \$keep_files,
    'help|h'       => sub { usage(); exit 0; },
) or die "Используйте --help для справки\n";

sub usage {
    print <<'EOF';
verify_dtran.pl — поразрядная сверка образов БЭСМ-6

  verify_dtran.pl --gold 2048 --silver 2222 --zone 0677 [--length N]
  verify_dtran.pl --gold-file G --silver-file S
  verify_dtran.pl --gold 2048 --silver 2222 --zone 0677 --sector 2

Опции:
  --gold DISK       Диск-эталона (напр. 2048)
  --silver DISK     Диск для проверки
  --gold-file FILE  Файл-дамп эталона
  --silver-file FILE Файл-дамп проверяемого
  -z, --zone ZZZZ   Начальная зона (восьмеричная)
  -l, --length N    Число зон (по умолчанию 1)
  --sector N        Сектор 0-3 (по умолчанию все 4)
  -v, --verbose     Подробный вывод
  --keep            Не удалять временные файлы
  -h, --help        Справка
EOF
}

# Геометрия диска БЭСМ-6:
#   1 зона (тракт) = 2000₈ = 1024₁₀ слов
#   1 сектор       =  400₈ =  256₁₀ слов
#   4 сектора в зоне
#   1 слово = 48 бит = 6 байт
my $WORDS_PER_ZONE  = 1024;        # 2000₈ слов
my $WORDS_PER_SEC   = 256;         #  400₈ слов
my $BYTES_PER_WORD  = 6;
my $BYTES_PER_ZONE  = $WORDS_PER_ZONE * $BYTES_PER_WORD;  # 6144
my $BYTES_PER_SEC   = $WORDS_PER_SEC  * $BYTES_PER_WORD;  # 1536

sub compare_block {
    my ($gf, $sf, $label, $skip, $size) = @_;
    my $cmd = "cmp -b";
    $cmd .= " -i $skip" if $skip > 0;
    $cmd .= " -n $size" if $size > 0;
    $cmd .= " $gf $sf";
    print "CMD: $cmd\n" if $verbose;

    my $first = `env LANG=en_US.UTF-8 $cmd 2>&1`;
    if ($? == 0) {
        print "\033[1;32m$label — OK\033[22;39m\n";
        return 0;
    }
    my $wc_cmd = $cmd . " | wc -l";
    my $diff_count = `$wc_cmd | awk '{print \$1}'`;
    chomp $diff_count;
    print "\033[1;31m$label — различий: $diff_count\033[22;39m\n";

    if ($first =~ /G(\d+).*byte (\d+)/) {
        my $base_zone = oct($1);
        my $abs_zone = $base_zone + int($2 / $BYTES_PER_ZONE);
        my $word = int(($2 % $BYTES_PER_ZONE) / $BYTES_PER_WORD);
        printf("  Первое: зона %04o, слово %04o\n", $abs_zone, $word);
    }
    return 1;
}

my $total_diffs = 0;
if ($gold_file ne '' && $silver_file ne '') {
    $total_diffs += compare_block($gold_file, $silver_file, "Файлы", 0, 0);
} elsif ($zone ne '') {
    my $base = oct($zone);
    my $tmpdir = tempdir(CLEANUP => !$keep_files);
    my @secs = ($sector >= 0) ? ($sector) : (0, 1, 2, 3);
    for (my $z = 0; $z < $length; $z++) {
        my $cz = sprintf("%04o", $base + $z);
        for my $s (@secs) {
            my $gf = "$tmpdir/G${cz}-S${s}";
            my $sf = "$tmpdir/S${cz}-S${s}";
            if ($gold_disk ne '') {
                system("besmtool dump $gold_disk --start=0$cz --length=1 --to-file=$gf >/dev/null 2>&1");
                next unless -e $gf && -s $gf >= $BYTES_PER_ZONE;
            }
            if ($silver_disk ne '') {
                system("besmtool dump $silver_disk --start=0$cz --length=1 --to-file=$sf >/dev/null 2>&1");
                next unless -e $sf && -s $sf >= $BYTES_PER_ZONE;
            }
            $total_diffs += compare_block($gf, $sf, "Зона $cz, сектор $s", $s * $BYTES_PER_SEC, $BYTES_PER_SEC);
        }
    }
}
if ($total_diffs == 0) {
    print "\033[1;32m=== ВСЕ СОВПАДАЮТ ===\033[22;39m\n";
} else {
    print "\033[1;31m=== ОБНАРУЖЕНЫ РАСХОЖДЕНИЯ ===\033[22;39m\n";
}
exit($total_diffs > 0 ? 1 : 0);
