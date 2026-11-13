use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use FCWebTest qw(load_cgi make_config cgi_path);

# --------------------------------------------------------------------------
# 2.17.9: the device-table editor's "Save changes" button is greyed out
# until there is something to write, and the server only writes when the
# editor is dirty. The button starts disabled on a clean load; a Preview
# round-trip re-emits _edited/_deleted inputs so it comes back enabled; the
# client script enables it on the first edit in ANY tab.
# --------------------------------------------------------------------------

my ($cfg) = make_config(); load_cgi($cfg);
my $src = do { local $/; open(my $f, '<', cgi_path()) or die $!; <$f> };

# --- server side: the Save button renders disabled unless edits are present -
like($src, qr/my \$has_edits = grep \{ \/_\(\?:edited\|deleted\)\\z\/ \} \$cgi->param\(\)/,
     'server detects pending edits from the submitted params');
like($src, qr/my \$save_dis  = \$has_edits \? '' : ' disabled'/,
     'clean load => the Save button carries the disabled attribute');
like($src, qr/value="save_table" id="save-table-btn"[^>]*\$save_dis>Save changes/,
     'the Save button is id-tagged and gated by $save_dis');

# Preview and Reject are never gated -- only Save is.
like($src, qr/value="preview_table" class="btn">Preview raw table/,
     'Preview raw table is always available');
unlike($src, qr/value="preview_table"[^>]*\$save_dis/,
     'Preview is not gated by the edit state');

# --- client side: the button follows the editorDirty flag -------------------
like($src, qr/function updateSaveState\(\) \{\s*var b = document\.getElementById\('save-table-btn'\);\s*if \(b\) b\.disabled = !editorDirty;/s,
     'updateSaveState() mirrors editorDirty onto the Save button');
like($src, qr/updateSaveState\(\);\s*\n\s*form\.addEventListener\('submit'/,
     'updateSaveState() runs once on load to set the initial state');

# every edit re-arms the dirty flag AND refreshes the Save button
my @rearm = $src =~ /editorDirty = true; formLeaving = false; updateSaveState\(\);/g;
is(scalar @rearm, 2, 'both edit paths (device rows + add-device) refresh the Save state');

# a catch-all input/change listener covers the Defaults/Email/General tabs too
# (onDevEdit is scoped to #dev-cards and would miss them)
like($src, qr/var markAnyEdit = function \(e\) \{ if \(e\.target && e\.target\.name\) markRowEdited\(e\.target\); \}/,
     'form-level catch-all marks edits made outside the device cards');
like($src, qr/form\.addEventListener\('input',  markAnyEdit\)/, 'catch-all bound to input');
like($src, qr/form\.addEventListener\('change', markAnyEdit\)/, 'catch-all bound to change');

# --- the disabled styling already exists in the stylesheet ------------------
my $cssf = $FindBin::Bin . '/../fetchconfig-web.css';
my $css  = do { open(my $f, '<', $cssf) or die $!; local $/; <$f> };
like($css, qr/\.btn:disabled, \.btn\[disabled\]/, 'disabled .btn has a greyed style');

done_testing();
