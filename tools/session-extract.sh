#!/usr/bin/env bash
# Turn an agent session transcript into a compact, code-free markdown source for wiki ingest.
# Supports: Claude Code (~/.claude/projects/*/<id>.jsonl) and GitHub Copilot in VS Code
# (~/.config/Code*/User/workspaceStorage/*/chatSessions/<id>.jsonl). Format is auto-detected.
# Keeps: user messages, assistant prose, one-line summaries of actions (files edited, commands, subagents).
# Drops: tool outputs, thinking, system reminders, file contents, code. Redacts obvious secrets.
# Needs only bash + perl (core, no modules) — both ship with Git for Windows, macOS and Linux. No python, no jq.
# Usage: tools/session-extract.sh [session-id | path.jsonl] [-o out.md]
#   no arg → most recently modified transcript (either tool) belonging to this workspace
set -euo pipefail
ws=$(cd "$(dirname "$0")/.." && pwd)
src=""; out=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; *) src="$1"; shift;; esac; done
command -v perl >/dev/null 2>&1 || { echo "session-extract: perl not found (it ships with Git for Windows, macOS and Linux)" >&2; exit 1; }
perl - "$ws" "$src" > "${out:-/dev/stdout}" <<'PL'
use strict; use warnings; no warnings 'recursion'; use utf8;
use File::Glob ':bsd_glob';
my ($ws, $src) = @ARGV;

# ---- minimal JSON decoder (no modules: JSON::PP is missing from some trimmed perls) ----
# objects → hash refs, arrays → array refs, true/false → 1/0, null → undef, strings → character strings
# (scans raw UTF-8 bytes — much faster than matching on decoded text — and decodes each string at the end)
my $J;
my %ESC = ('"' => '"', '\\' => '\\', '/' => '/', b => "\x08", f => "\x0c", n => "\n", r => "\r", t => "\t");
sub junesc {   # \uXXXX (surrogate pair in $hi/$lo, or single unit in $u)
    my ($hi, $lo, $u) = @_;
    my $n = defined $hi ? 0x10000 + ((hex($hi) - 0xD800) << 10) + (hex($lo) - 0xDC00) : hex $u;
    my $c = chr($n >= 0xD800 && $n <= 0xDFFF ? 0xFFFD : $n); utf8::encode($c); return $c;
}
sub jstr {   # opening quote already consumed
    my $raw = '';
    while (1) {   # bounded repeat: old perls cap complex quantifiers at 32766 iterations
        my $at = pos($$J);
        $$J =~ /\G([^"\\]*(?:\\.[^"\\]*){0,30000})/gcs; $raw .= $1;
        last if $$J =~ /\G"/gc;
        die "json\n" if pos($$J) == $at;
    }
    $raw =~ s/\\(?:(["\\\/bfnrt])|u([dD][89abAB][0-9a-fA-F]{2})\\u([dD][c-fC-F][0-9a-fA-F]{2})|u([0-9a-fA-F]{4})|(.))/
              defined $1 ? $ESC{$1} : defined $5 ? die("json\n") : junesc($2, $3, $4)/gsex if index($raw, '\\') >= 0;
    utf8::decode($raw);
    return $raw;
}
sub jval {
    $$J =~ /\G[ \t\r\n]*/gc;
    return jstr() if $$J =~ /\G"/gc;
    if ($$J =~ /\G\{/gc) {
        my %h;
        return \%h if $$J =~ /\G[ \t\r\n]*\}/gc;
        while (1) {
            $$J =~ /\G[ \t\r\n]*"/gc or die "json\n";
            my $k = jstr();
            $$J =~ /\G[ \t\r\n]*:/gc or die "json\n";
            $h{$k} = jval();
            next if $$J =~ /\G[ \t\r\n]*,/gc;
            return \%h if $$J =~ /\G[ \t\r\n]*\}/gc;
            die "json\n";
        }
    }
    if ($$J =~ /\G\[/gc) {
        my @a;
        return \@a if $$J =~ /\G[ \t\r\n]*\]/gc;
        while (1) {
            push @a, jval();
            next if $$J =~ /\G[ \t\r\n]*,/gc;
            return \@a if $$J =~ /\G[ \t\r\n]*\]/gc;
            die "json\n";
        }
    }
    return 0 + $1 if $$J =~ /\G(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)/gc;
    return 1 if $$J =~ /\Gtrue/gc;
    return 0 if $$J =~ /\Gfalse/gc;
    return undef if $$J =~ /\Gnull/gc;
    die "json\n";
}
sub decode {   # → (ok, value)
    my $s = shift;
    $J = \$s; pos($s) = 0;
    my $v; my $ok = eval { $v = jval(); $s =~ /\G[ \t\r\n]*\z/gc or die "json\n"; 1 };
    return ($ok ? 1 : 0, $v);
}

# ---- helpers ----
sub has  { my $x = shift; return defined $x && (ref $x || length $x) }                         # non-empty string / any ref
sub hget { my ($h, $k) = @_; return ref $h eq 'HASH' ? $h->{$k} : undef }
sub slashes  { my $p = shift; $p =~ tr{\\}{/}; return $p }
sub basename { my $p = slashes(shift); $p =~ s{/+$}{}; $p =~ s{.*/}{}; return $p }
sub dirname  { my $p = slashes(shift); $p =~ s{/+$}{}; return $p =~ s{/[^/]*$}{} ? $p : '.' }
sub realp    { my $p = shift; my $r = eval { require Cwd; Cwd::realpath($p) }; return slashes(defined $r ? $r : $p) }
sub lines_of { my $p = shift; open my $fh, '<', $p or return (); my @l = <$fh>; close $fh; return @l }
sub first_line { my $p = shift; open my $fh, '<', $p or return ''; my $l = <$fh>; close $fh; return defined $l ? $l : '' }
sub pystr { my $x = shift; return defined $x ? $x : 'None' }

# ---- locate transcripts ----
# Git Bash: HOME (/c/Users/x) and USERPROFILE (C:\Users\x) are usually the same folder, but HOME can be remapped — try both once
my %seen; my @homes = grep { has($_) && -d $_ && !$seen{ join ':', (stat _)[0, 1] }++ } map { defined $_ ? slashes($_) : undef } ($ENV{HOME}, $ENV{USERPROFILE});
my @CLAUDE = map { bsd_glob("$_/.claude/projects/*/*.jsonl") } @homes;
my @vs_user = map { ("$_/.config/Code*/User", "$_/Library/Application Support/Code*/User", "$_/AppData/Roaming/Code*/User") } @homes;   # Linux, macOS, Windows
push @vs_user, slashes($ENV{APPDATA}) . '/Code*/User' if has($ENV{APPDATA});
%seen = ();
my @VSCODE = grep { !$seen{$_}++ } map { bsd_glob("$_/workspaceStorage/*/chatSessions/*.jsonl") } @vs_user;
my %is_vscode = map { $_ => 1 } @VSCODE;

sub vscode_ws {   # workspace folder a VS Code chat session belongs to
    my $path = shift;
    my $f = dirname(dirname($path)) . '/workspace.json';
    open my $fh, '<', $f or return '';
    local $/; my $txt = <$fh>; close $fh;
    my ($ok, $meta) = decode($txt);
    return '' unless $ok && ref $meta eq 'HASH';
    my $folder = $meta->{folder}; $folder = '' unless defined $folder && !ref $folder;
    $folder =~ s{file://}{}g;
    utf8::encode($folder); $folder =~ s/%([0-9A-Fa-f]{2})/chr hex $1/ge; utf8::decode($folder);
    $folder =~ s{^/(?=[A-Za-z]:)}{};   # file:///C:/… on Windows
    return $folder;
}
sub claude_ws {
    my $path = shift;
    for my $line (lines_of($path)) {
        my ($ok, $o) = decode($line);
        return '' unless $ok;
        my $cwd = hget($o, 'cwd');
        return $cwd if has($cwd) && !ref $cwd;
    }
    return '';
}
sub resolve {
    return $src if length $src && -f $src;
    if (length $src) {
        for my $p (@CLAUDE, @VSCODE) { return $p if basename($p) eq "$src.jsonl" }
        print STDERR "transcript not found for session $src\n"; exit 1;
    }
    # same workspace; Claude transcripts of a renamed folder still match by basename
    my %mt = map { $_ => ((stat $_)[9] || 0) } @CLAUDE, @VSCODE;
    my @cands = sort { $mt{$b} <=> $mt{$a} } keys %mt;
    splice @cands, 200 if @cands > 200;
    my $wsr = realp($ws);
    for my $p (@cands) {
        my $w = $is_vscode{$p} ? vscode_ws($p) : claude_ws($p);
        next unless length $w;
        return $p if realp($w) eq $wsr || basename($w) eq basename($ws);
    }
    print STDERR "no transcript found for this workspace\n"; exit 1;
}

# ---- cleaning ----
my @SECRET = (qr/sk-[A-Za-z0-9_-]{16,}/, qr/gh[pousr]_[A-Za-z0-9]{20,}/, qr/AKIA[0-9A-Z]{16}/, qr/xox[abpr]-[A-Za-z0-9-]{10,}/,
              qr/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/,
              qr/(?i)(password|passwd|secret|token|api[_-]?key)\s*[:=]\s*\S+/);
sub redact { my $s = shift; $s =~ s/$_/[REDACTED]/g for @SECRET; return $s }
sub strip  { my $s = shift; $s =~ s/^\s+//; $s =~ s/\s+$//; return $s }
sub clean_user {
    my $s = shift; return '' unless defined $s && !ref $s;
    $s =~ s{<system-reminder>[\s\S]*?</system-reminder>}{}g;
    $s =~ s{<(local-command-[a-z]+|command-[a-z]+)>[\s\S]*?</\1>}{}g;
    $s =~ s{<pasted_content[^>]*>([\s\S]*?)</pasted_content[^>]*>}
           {'[pasted: ' . substr(strip($1), 0, 1500) . (length($1) > 1500 ? ' …(truncated)' : '') . ']'}ge;
    $s =~ s/```[\s\S]*?```/[code block omitted]/g;
    return strip($s);
}
sub clean_assistant {
    my $s = shift; return '' unless defined $s && !ref $s;
    $s =~ s/```(mermaid)?[\s\S]*?```/defined $1 ? '[diagram omitted]' : '[code omitted]'/ge;
    return strip($s);
}

my (@turns, @acts, %meta);
sub flush_acts {
    return unless @acts;
    my %d; push @turns, 'Actions: ' . join('; ', grep { !$d{$_}++ } @acts); @acts = ();
}
sub say { my ($who, $s) = @_; return unless has($s); flush_acts(); push @turns, "**$who:** $s" }

# ---- Claude Code transcript ----
sub claude_action {
    my $b = shift;
    my $n = hget($b, 'name'); $n = '?' unless defined $n;
    my $i = hget($b, 'input'); $i = {} unless ref $i eq 'HASH';
    my $g = sub { my ($k, $d) = @_; return defined $i->{$k} && !ref $i->{$k} ? $i->{$k} : $d };
    return "$n " . $g->('file_path', '') if $n eq 'Edit' || $n eq 'Write' || $n eq 'NotebookEdit';
    if ($n eq 'Bash') {
        my $d = $g->('description', '');
        unless (length $d) { ($d) = split /\r\n|[\n\r\x0b\x0c\x1c-\x1e\x85\x{2028}\x{2029}]/, $g->('command', ''); $d = substr(defined $d ? $d : '', 0, 100) }
        return "Bash: $d";
    }
    return 'Subagent ' . $g->('subagent_type', 'general') . ' [' . $g->('model', 'default') . ']: ' . $g->('description', '') if $n eq 'Agent';
    return 'Skill ' . $g->('skill', 'None') if $n eq 'Skill';
    return undef if $n =~ /^(?:Read|Grep|Glob|ToolSearch|TodoWrite)$/;
    return $n;
}
sub claude {
    my $path = shift;
    $meta{tool} = 'claude-code';
    for my $line (lines_of($path)) {
        my ($ok, $o) = decode($line);
        next unless $ok && ref $o eq 'HASH';
        my $type = defined $o->{type} ? $o->{type} : '';
        next unless $type eq 'user' || $type eq 'assistant';
        next if $o->{isSidechain} || $o->{isMeta};
        $meta{start} = $o->{timestamp} unless exists $meta{start};
        $meta{end} = $o->{timestamp};
        $meta{cwd} = $o->{cwd} unless exists $meta{cwd};
        $meta{session} = $o->{sessionId} unless exists $meta{session};
        my $c = hget($o->{message}, 'content');
        my @blocks = !defined $c ? () : !ref $c ? ({ type => 'text', text => $c }) : ref $c eq 'ARRAY' ? @$c : ();
        for my $b (@blocks) {
            next unless ref $b eq 'HASH';
            my $t = defined $b->{type} ? $b->{type} : '';
            if    ($type eq 'user'      && $t eq 'text') { say('User', clean_user($b->{text})) }
            elsif ($type eq 'assistant' && $t eq 'text') { say('Assistant', clean_assistant($b->{text})) }
            elsif ($type eq 'assistant' && $t eq 'tool_use') { my $a = claude_action($b); push @acts, $a if has($a) }
        }
    }
}

# ---- GitHub Copilot (VS Code) chat session ----
sub iso {   # epoch milliseconds → ISO-8601 UTC
    my $ms = shift;
    return $ms unless defined $ms && !ref $ms && $ms =~ /^-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?$/;
    my $sec = int($ms / 1000); my $us = int(($ms - 1000 * $sec) * 1000 + 0.5);
    my @t = gmtime $sec;
    return sprintf('%04d-%02d-%02dT%02d:%02d:%02d', $t[5] + 1900, $t[4] + 1, @t[3, 2, 1, 0]) . ($us ? sprintf('.%06d', $us) : '') . '+00:00';
}
sub val { my $m = shift; return ref $m eq 'HASH' ? (defined $m->{value} ? $m->{value} : '') : (defined $m ? $m : '') }
sub vscode {
    my $path = shift;
    # incremental patch log: kind 0 = initial state, 1 = set value at path k, 2 = append (optionally truncate at i), 3 = delete
    my $st = {};
    LINE: for my $line (lines_of($path)) {
        my ($ok, $o) = decode($line);
        next unless $ok && ref $o eq 'HASH';
        my $kind = defined $o->{kind} ? $o->{kind} : -1;
        if ($kind == 0) { $st = ref $o->{v} ? $o->{v} : {}; next }
        my @k = ref $o->{k} eq 'ARRAY' ? @{ $o->{k} } : ();
        next unless @k;
        my $last = pop @k; my $parent = $st;
        for my $p (@k) {
            if    (ref $parent eq 'HASH'  && exists $parent->{$p}) { $parent = $parent->{$p} }
            elsif (ref $parent eq 'ARRAY' && $p =~ /^\d+$/ && $p < @$parent) { $parent = $parent->[$p] }
            else  { next LINE }
        }
        my $isidx = ref $parent eq 'ARRAY' && $last =~ /^\d+$/ && $last < @$parent;
        next unless ref $parent eq 'HASH' || $isidx;
        if ($kind == 1) { if ($isidx) { $parent->[$last] = $o->{v} } else { $parent->{$last} = $o->{v} } }
        elsif ($kind == 2) {
            my $arr = $isidx ? $parent->[$last] : $parent->{$last};
            next unless ref $arr eq 'ARRAY';
            my $v = exists $o->{v} ? $o->{v} : [];
            splice @$arr, $o->{i} if defined $o->{i} && $o->{i} =~ /^\d+$/ && $o->{i} < @$arr;
            push @$arr, ref $v eq 'ARRAY' ? @$v : $v;
        }
        elsif ($kind == 3) { if ($isidx) { splice @$parent, $last, 1 } else { delete $parent->{$last} } }
    }
    $st = {} unless ref $st eq 'HASH';
    @meta{qw(tool session cwd)} = ('copilot-vscode', $st->{sessionId}, vscode_ws($path));
    my @reqs = grep { ref $_ eq 'HASH' && !$_->{hiddenFromTranscript} } (ref $st->{requests} eq 'ARRAY' ? @{ $st->{requests} } : ());
    @meta{qw(start end)} = (iso($reqs[0]{timestamp}), iso($reqs[-1]{timestamp})) if @reqs;
    for my $r (@reqs) {
        my $m = val($r->{message}); $m = hget($r->{message}, 'text') unless has($m);
        say('User', clean_user($m));
        my @md;
        for my $p (ref $r->{response} eq 'ARRAY' ? @{ $r->{response} } : ()) {
            next unless ref $p eq 'HASH';
            my $kind = $p->{kind};
            if (!defined $kind) { push @md, $p->{value} if exists $p->{value} && defined $p->{value} && !ref $p->{value} }
            elsif ($kind eq 'toolInvocationSerialized') {
                if (@md) { say('Assistant', clean_assistant(join '', @md)); @md = () }
                my $tid = defined $p->{toolId} ? $p->{toolId} : '';
                next if $tid =~ /^(?:manage_todo_list|copilot_readFile|read_file|copilot_findTextInFiles|grep_search|file_search)$/;
                my $msg = val($p->{pastTenseMessage}); $msg = val($p->{invocationMessage}) unless has($msg);
                $msg = '' if ref $msg; $msg =~ s/\s+/ /g; $msg = substr($msg, 0, 120);
                push @acts, length $msg ? "$tid: $msg" : $tid;
            }
            elsif ($kind eq 'textEditGroup') {
                my $uri = hget($p->{uri}, 'path'); $uri = hget($p->{uri}, 'fsPath') unless has($uri);
                push @acts, "Edit $uri" if has($uri);
            }
        }
        say('Assistant', clean_assistant(join '', @md)) if @md;
    }
}

my $path = resolve();
my $first = first_line($path);
if ($first =~ /"kind"/ && $first =~ /"requests"/) { vscode($path) } else { claude($path) }
flush_acts();
my $out = "---\n";
$out .= "$_: " . pystr($meta{$_}) . "\n" for qw(tool session cwd start end);
$out .= "type: session-transcript\n---\n\n" . redact(join "\n\n", @turns) . "\n";
utf8::encode($out);
binmode STDOUT; print $out;
PL
