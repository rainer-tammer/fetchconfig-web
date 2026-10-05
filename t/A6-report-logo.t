use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config);
use File::Temp qw(tempdir);

my $repdir = tempdir(CLEANUP => 1);
my ($cfg) = make_config();
load_cgi($cfg); main::read_config();

# valid_logo_name: case-preserving, extension (case-insensitive), no traversal
ok( main::valid_logo_name('Logo.PNG'),   'mixed-case name accepted');
ok( main::valid_logo_name('a.jpeg'),     '.jpeg accepted');
ok( main::valid_logo_name('x.GIF'),      'uppercase ext accepted');
ok(!main::valid_logo_name('../evil.png'),'traversal rejected');
ok(!main::valid_logo_name('a/b.png'),    'separator rejected');
ok(!main::valid_logo_name('x.bmp'),      'non-image ext rejected');
ok(!main::valid_logo_name(''),           'empty rejected');

# image_magic_type
is(main::image_magic_type("\x89PNG\x0d\x0a\x1a\x0a"), 'png', 'PNG magic');
is(main::image_magic_type("\xff\xd8\xff\xe0"),        'jpg', 'JPEG magic');
is(main::image_magic_type('GIF89a'),                  'gif', 'GIF89a magic');
is(main::image_magic_type('GIF87a'),                  'gif', 'GIF87a magic');
ok(!defined main::image_magic_type('not an image'),   'non-image rejected');

# list_report_images: case-preserved, sorted, extensions filtered, cap honoured
open(my $f1,'>',"$repdir/Logo.PNG"); print $f1 "x"; close($f1);
open(my $f2,'>',"$repdir/logo.png"); print $f2 "x"; close($f2);
open(my $f3,'>',"$repdir/pic.jpg");  print $f3 "x"; close($f3);
open(my $f4,'>',"$repdir/readme.txt");print $f4 "x"; close($f4);
my ($imgs,$total) = main::list_report_images($repdir, 25);
is($total, 3, 'counts 3 images (excludes .txt)');
is_deeply($imgs, [sort qw(Logo.PNG logo.png pic.jpg)], 'case preserved + sorted + filtered');

# cap
for my $i (1..30) { open(my $g,'>',"$repdir/i$i.png"); print $g 'x'; close($g); }
my ($capped,$tot2) = main::list_report_images($repdir, 25);
is(scalar(@$capped), 25, 'list capped at 25');
ok($tot2 > 25, 'total reflects real count');

# logo_data_uri: inline base64 preview, correct MIME, rejects non-image/oversize
use File::Temp qw(tempdir);
my $d = tempdir(CLEANUP => 1);
open(my $p,'>',"$d/a.png"); binmode $p; print $p "\x89PNG\x0d\x0a\x1a\x0a".("A"x50); close $p;
open(my $j,'>',"$d/b.jpg"); binmode $j; print $j "\xff\xd8\xff\xe0".("A"x50); close $j;
open(my $g,'>',"$d/c.gif"); binmode $g; print $g "GIF89a".("A"x50); close $g;
open(my $x,'>',"$d/x.png"); binmode $x; print $x "not an image"; close $x;
like(main::logo_data_uri("$d/a.png"), qr{^data:image/png;base64,}, 'PNG -> data:image/png');
like(main::logo_data_uri("$d/b.jpg"), qr{^data:image/jpeg;base64,}, 'JPG -> data:image/jpeg');
like(main::logo_data_uri("$d/c.gif"), qr{^data:image/gif;base64,}, 'GIF -> data:image/gif');
ok(!defined main::logo_data_uri("$d/x.png"), 'non-image -> undef');
ok(!defined main::logo_data_uri("$d/nope.png"), 'missing file -> undef');

done_testing();
