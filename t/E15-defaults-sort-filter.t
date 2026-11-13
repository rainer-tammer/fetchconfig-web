use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# Defaults tab (device editor): the per-model default: cards are shown sorted
# by model name, and a model-name filter box hides non-matching cards -- both
# DISPLAY ONLY. The on-disk default: order must be preserved on save (the save
# path walks records by index, not DOM order), so this is a view concern only.
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg); main::read_config();   # compiles the whole .cgi
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

# --- Sort (server side) ----------------------------------------------------
like($src, qr/\@def_admin/,
     'admin default cards collected separately for sorting');
like($src, qr/map \{ \$_->\[1\] \} sort \{ \$a->\[0\] cmp \$b->\[0\] \} \@def_admin/,
     'admin default cards are sorted by model name for display');
like($src, qr/sort \{ lc\(\$a\) cmp lc\(\$b\) \} \@def_model_order/,
     'read-only merged default boxes are sorted by model name');
# The sort must be documented as display-only (save keeps on-disk order).
like($src, qr/on-disk default: order is (?:unchanged|preserved)/i,
     'sort is documented as display-only (on-disk order preserved)');

# --- Filter box (server side) ---------------------------------------------
like($src, qr/id="edit-def-filter"/,     'Defaults tab has a model filter input');
like($src, qr/id="edit-def-clear"/,      'Defaults tab filter has a Clear button');
like($src, qr/id="edit-def-no-match"/,   'Defaults tab has a "no match" message');
# read-only merged boxes carry data-model so the JS can read the model
like($src, qr/rec-card rec-readonly" data-model=/,
     'read-only merged default box carries data-model');

# --- Filter (client side) --------------------------------------------------
like($src, qr/function filterDefaults\(\)/, 'client-side filterDefaults() present');
like($src, qr/function defCardModel\(card\)/, 'defCardModel() reads a card model');
# reads admin card model via the .rec-model select, read-only via data-model
like($src, qr/card\.querySelector\('\.rec-model'\)/, 'admin model read from .rec-model');
like($src, qr/getAttribute\('data-model'\)/,         'read-only model read from data-model');
like($src, qr/editDefFilter\.addEventListener\('input', filterDefaults\)/,
     'filter runs as the user types');

# --- the model of an EXISTING default: entry is LOCKED (it is the entry key) --
my $def_card = main::render_record_card('r0', { kind=>'default', model=>'cisco-ios', opts=>[] }, 'default');
unlike($def_card, qr/<select name="r0_model"/,
       'default card: model is NOT an editable dropdown');
like($def_card, qr/<input type="hidden" name="r0_model" class="rec-model" value="cisco-ios">/,
       'default card: model posts via a hidden .rec-model field (filter/JS still read it)');
like($def_card, qr/rec-model-fixed/, 'default card: model shown as a locked label');

# a device card keeps its editable model dropdown
my $dev_card = main::render_record_card('r1',
    { kind=>'device', model=>'cisco-ios', id=>'sw1', host=>'10.0.0.1', opts=>[] }, 'device');
like($dev_card, qr/<select name="r1_model" class="rec-model">/,
       'device card: model stays an editable dropdown');

done_testing();
