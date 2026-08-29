#!/usr/bin/env bash
# =============================================================================
# the-whole-shebang/tui/action - What the interface can do, as data
# =============================================================================
# Part of the-whole-shebang. Built on nutshell, sourced on its own.
# https://github.com/orgrinrt/the-whole-shebang
#
# Depends on nothing else in the collection, on purpose: a key line, a help
# screen and a palette are all reads of this, and a module they all import must
# not drag a terminal in with it.
#
# An action carries an id, a scope, a label, the keys that reach it, and
# optionally a handler. The dispatch that used to be a `case` over characters
# becomes a lookup here, which is what makes the derived surfaces impossible to
# drift: `?` lists what is registered, the palette searches what is registered,
# and a keymap rebinds what is registered.
#
# **A binding is named, never spelled.** `bracket-left` rather than `[`. The
# reason is a real one rather than tidiness: on a Finnish layout `[` is AltGr+8
# and a bare console does not deliver it, so a key written as a character in
# the source is a key some keyboards cannot press and nobody can rebind. A name
# can be looked up, printed, and pointed at from a config file.
#
# Usage:
#   use shebang::tui::action
#
#   tui_action_reset
#   tui_action_add section-next main "to the next section" "bracket-right ctrl-down"
#   tui_action_bind section-next "ctrl-down"          # what a keymap does
#   tui_action_for main "$TUI_KEY"                    # prints the id, or fails
# =============================================================================

[[ -n "${_SHEBANG_TUI_ACTION_SH:-}" ]] && return 0
readonly _SHEBANG_TUI_ACTION_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'tui: source nutshell first (. path/to/nutshell/init)\n' >&2
    return 1
fi

# -----------------------------------------------------------------------------
# The register
# -----------------------------------------------------------------------------

declare -ga TUI_ACTION_ID=()
declare -ga TUI_ACTION_SCOPE=()     # main | filter | palette
declare -ga TUI_ACTION_LABEL=()
declare -ga TUI_ACTION_KEYS=()      # names, space separated, possibly empty
declare -ga TUI_ACTION_HANDLER=()

# Bumped whenever anything about the register changes. Anything derived from it
# and worth caching, a key line most of all, keeps the number it was built at
# and rebuilds when the two differ. Without it a surface built once stays built:
# a keymap read after the defaults were registered leaves the bottom line naming
# keys that no longer do anything, and the bottom line is the one thing nobody
# re-reads, so it stays wrong quietly.
declare -gi TUI_ACTION_GEN=0

# The scopes, and what each one means.
#
# `main` is the ordinary interface, and is what `?` lists. `filter` is the
# typing mode, where nearly every key types a character and only a few keep a
# meaning, so it is a separate namespace rather than a subset. `palette` is
# reachable by name and by nothing else, which is where a thing goes when it is
# worth having and not worth a key.
#
# Every action is in the palette whatever its scope. A palette that searched
# only the actions nobody gave a key to would be a list of leftovers.

# -----------------------------------------------------------------------------
# Naming a key
# -----------------------------------------------------------------------------

# The punctuation, by name. Everything else the reader already names for us:
# `up`, `ctrl-down`, `pgup`, `enter`, `space`, `tab`, `backspace`, `esc`, and a
# letter is its own name.
#
# Only the characters a keyboard layout can move or withhold are in here, which
# is why the list is punctuation and not the alphabet.
_tui_action_name_of() {
    case "$1" in
        '/')  printf 'slash' ;;
        '?')  printf 'question' ;;
        '[')  printf 'bracket-left' ;;
        ']')  printf 'bracket-right' ;;
        '\')  printf 'backslash' ;;
        ',')  printf 'comma' ;;
        '.')  printf 'period' ;;
        '-')  printf 'minus' ;;
        '+')  printf 'plus' ;;
        '=')  printf 'equals' ;;
        ':')  printf 'colon' ;;
        ';')  printf 'semicolon' ;;
        "'")  printf 'apostrophe' ;;
        '"')  printf 'quote' ;;
        '*')  printf 'star' ;;
        '#')  printf 'hash' ;;
        '@')  printf 'at' ;;
        '%')  printf 'percent' ;;
        '^')  printf 'caret' ;;
        '&')  printf 'ampersand' ;;
        '~')  printf 'tilde' ;;
        '<')  printf 'less' ;;
        '>')  printf 'greater' ;;
        '(')  printf 'paren-left' ;;
        ')')  printf 'paren-right' ;;
        '{')  printf 'brace-left' ;;
        '}')  printf 'brace-right' ;;
        '!')  printf 'bang' ;;
        '$')  printf 'dollar' ;;
        '|')  printf 'pipe' ;;
        '_')  printf 'underscore' ;;
        '`')  printf 'backtick' ;;
        # The control bytes a terminal sends for the emacs-style movement keys.
        # The reader hands these through raw, and a raw byte is not something a
        # config file can name or a key line can print.
        $'\002') printf 'ctrl-b' ;;
        $'\006') printf 'ctrl-f' ;;
        $'\016') printf 'ctrl-n' ;;
        $'\020') printf 'ctrl-p' ;;
        *)    printf '%s' "$1" ;;
    esac
}

#[pub]
# The name of a key as the reader gave it. A key with no name of its own is its
# own name, so this is total and never fails.
# Usage: tui_action_key_name <raw-key>
tui_action_key_name() { _tui_action_name_of "$1"; }

#[pub]
# The character a name stands for, for printing it on a key line. A name that
# stands for no character (`ctrl-down`, `pgup`) prints as itself, which is what
# a reader wants to see anyway.
# Usage: tui_action_key_char <name>
tui_action_key_char() {
    local c
    case "$1" in
        slash) c='/' ;;         question) c='?' ;;
        bracket-left) c='[' ;;  bracket-right) c=']' ;;
        backslash) c='\' ;;     comma) c=',' ;;
        period) c='.' ;;        minus) c='-' ;;
        plus) c='+' ;;          equals) c='=' ;;
        colon) c=':' ;;         semicolon) c=';' ;;
        apostrophe) c="'" ;;    quote) c='"' ;;
        star) c='*' ;;          hash) c='#' ;;
        at) c='@' ;;            percent) c='%' ;;
        caret) c='^' ;;         ampersand) c='&' ;;
        tilde) c='~' ;;         less) c='<' ;;
        greater) c='>' ;;       paren-left) c='(' ;;
        paren-right) c=')' ;;   brace-left) c='{' ;;
        brace-right) c='}' ;;   bang) c='!' ;;
        dollar) c='$' ;;        pipe) c='|' ;;
        underscore) c='_' ;;    backtick) c='`' ;;
        *) c="$1" ;;
    esac
    printf '%s' "$c"
}

# -----------------------------------------------------------------------------
# Building the register
# -----------------------------------------------------------------------------

#[pub]
# Empty the register. Always before building one, or a second screen answers to
# the first one's keys.
# Usage: tui_action_reset
tui_action_reset() {
    TUI_ACTION_ID=(); TUI_ACTION_SCOPE=(); TUI_ACTION_LABEL=()
    TUI_ACTION_KEYS=(); TUI_ACTION_HANDLER=()
    TUI_ACTION_GEN=$(( TUI_ACTION_GEN + 1 ))
}

# Where an id sits, or nothing and a non-zero status.
_tui_action_index() {
    local id="$1" i
    for i in "${!TUI_ACTION_ID[@]}"; do
        [[ "${TUI_ACTION_ID[$i]}" == "$id" ]] && { printf '%d' "$i"; return 0; }
    done
    return 1
}

#[pub]
# Register one. Keys are names, space separated, and may be empty for an action
# that lives in the palette alone.
#
# A second add of the same id replaces the first rather than appending, so a
# caller that rebuilds its register does not accumulate duplicates it would
# then have to notice.
# Usage: tui_action_add <id> <scope> <label> [keys] [handler]
tui_action_add() {
    local id="${1:-}" scope="${2:-}" label="${3:-}" keys="${4:-}" handler="${5:-}" i
    [[ -n "$id" ]] || { printf 'tui_action_add: an action needs an id\n' >&2; return 1; }
    case "$scope" in
        main|filter|palette) ;;
        *) printf 'tui_action_add: %s: scope is main, filter or palette, not %s\n' \
               "$id" "${scope:-empty}" >&2; return 1 ;;
    esac
    if i="$(_tui_action_index "$id")"; then
        TUI_ACTION_SCOPE[$i]="$scope"; TUI_ACTION_LABEL[$i]="$label"
        TUI_ACTION_KEYS[$i]="$keys";   TUI_ACTION_HANDLER[$i]="$handler"
        TUI_ACTION_GEN=$(( TUI_ACTION_GEN + 1 ))
        return 0
    fi
    TUI_ACTION_ID+=("$id");     TUI_ACTION_SCOPE+=("$scope")
    TUI_ACTION_LABEL+=("$label"); TUI_ACTION_KEYS+=("$keys")
    TUI_ACTION_HANDLER+=("$handler")
    TUI_ACTION_GEN=$(( TUI_ACTION_GEN + 1 ))
}

#[pub]
# Point an action at different keys, replacing whatever it had. This is what a
# keymap does, and it is deliberately not additive: a keymap that could only
# add would leave the default binding in place beside the new one, which is how
# a rebind ends up not being one.
# Usage: tui_action_bind <id> <keys>
tui_action_bind() {
    local id="${1:-}" i
    i="$(_tui_action_index "$id")" || {
        printf 'tui_action_bind: no action called %s\n' "${id:-empty}" >&2; return 1; }
    TUI_ACTION_KEYS[$i]="${2:-}"
    TUI_ACTION_GEN=$(( TUI_ACTION_GEN + 1 ))
}

#[pub]
# The keys an action answers to, as names.
# Usage: tui_action_keys <id>
tui_action_keys() {
    local i; i="$(_tui_action_index "${1:-}")" || return 1
    printf '%s' "${TUI_ACTION_KEYS[$i]}"
}

#[pub]
# Usage: tui_action_label <id>
tui_action_label() {
    local i; i="$(_tui_action_index "${1:-}")" || return 1
    printf '%s' "${TUI_ACTION_LABEL[$i]}"
}

#[pub]
# Usage: tui_action_scope <id>
tui_action_scope() {
    local i; i="$(_tui_action_index "${1:-}")" || return 1
    printf '%s' "${TUI_ACTION_SCOPE[$i]}"
}

#[pub]
# The function that runs it, empty where the owner dispatches on the id itself.
# Usage: tui_action_handler <id>
tui_action_handler() {
    local i; i="$(_tui_action_index "${1:-}")" || return 1
    printf '%s' "${TUI_ACTION_HANDLER[$i]}"
}

#[pub]
# Every id, in the order registered, or every id in one scope.
# Usage: tui_action_ids [scope]
tui_action_ids() {
    local want="${1:-}" i
    for i in "${!TUI_ACTION_ID[@]}"; do
        [[ -z "$want" || "${TUI_ACTION_SCOPE[$i]}" == "$want" ]] || continue
        printf '%s\n' "${TUI_ACTION_ID[$i]}"
    done
}

# -----------------------------------------------------------------------------
# Looking one up
# -----------------------------------------------------------------------------

#[pub]
# The action a key reaches in a scope, by id, or a non-zero status and nothing.
#
# The key may be given raw as the reader produced it or by name, because the
# caller has the raw one and a test has the readable one, and refusing either
# would only mean every caller converting first.
# Usage: tui_action_for <scope> <key>
tui_action_for() {
    local scope="${1:-}" key="${2:-}" name i k
    [[ -n "$key" ]] || return 1
    name="$(_tui_action_name_of "$key")"
    for i in "${!TUI_ACTION_ID[@]}"; do
        [[ "${TUI_ACTION_SCOPE[$i]}" == "$scope" ]] || continue
        for k in ${TUI_ACTION_KEYS[$i]}; do
            if [[ "$k" == "$name" ]]; then
                printf '%s' "${TUI_ACTION_ID[$i]}"; return 0
            fi
        done
    done
    return 1
}

#[pub]
# Keys bound to more than one action in the same scope, one "scope key id id"
# line each. A keymap that collides is a keymap somebody wrote by hand, and the
# only thing worse than the collision is it being silent: the first action wins
# and the second key does nothing, with nothing anywhere saying why.
# Usage: tui_action_conflicts
tui_action_conflicts() {
    local i j k m scope found rc=1
    for i in "${!TUI_ACTION_ID[@]}"; do
        scope="${TUI_ACTION_SCOPE[$i]}"
        for k in ${TUI_ACTION_KEYS[$i]}; do
            found=""
            for j in "${!TUI_ACTION_ID[@]}"; do
                (( j > i )) || continue
                [[ "${TUI_ACTION_SCOPE[$j]}" == "$scope" ]] || continue
                for m in ${TUI_ACTION_KEYS[$j]}; do
                    [[ "$m" == "$k" ]] && found+=" ${TUI_ACTION_ID[$j]}"
                done
            done
            [[ -n "$found" ]] || continue
            printf '%s %s %s%s\n' "$scope" "$k" "${TUI_ACTION_ID[$i]}" "$found"
            rc=0
        done
    done
    return $rc
}

# -----------------------------------------------------------------------------
# The surfaces derived from it
# -----------------------------------------------------------------------------

#[pub]
# The key line, as "keys<tab>label" lines, for a help screen to print. Actions
# with no key are left out, since a key line is about keys; the palette is
# where they are reachable.
# Usage: tui_action_lines [scope]
tui_action_lines() {
    local want="${1:-main}" i k out
    for i in "${!TUI_ACTION_ID[@]}"; do
        [[ "${TUI_ACTION_SCOPE[$i]}" == "$want" ]] || continue
        [[ -n "${TUI_ACTION_KEYS[$i]}" ]] || continue
        out=""
        for k in ${TUI_ACTION_KEYS[$i]}; do
            out+="${out:+ }$(tui_action_key_char "$k")"
        done
        printf '%s\t%s\n' "$out" "${TUI_ACTION_LABEL[$i]}"
    done
}

# Is this position the start of a word? The string's own start counts, and so
# does anything after a separator. A palette lives on this: somebody typing two
# letters is nearly always typing initials.
_tui_action_boundary() {
    local hay="$1" i="$2" prev
    (( i == 0 )) && return 0
    prev="${hay:$(( i - 1 )):1}"
    case "$prev" in ' '|'-'|'_'|'.'|'/') return 0 ;; *) return 1 ;; esac
}

# Does the needle appear in the haystack in order, letting anything sit between
# its letters? Prints "boundaries start span", so the caller can rank.
#
# Two passes, because a plain leftmost match cannot tell `sn` in `section-next`
# from `sn` in `section-prev`: both consume the `n` of `section` and score the
# same. Preferring a letter that begins a word finds the `n` of `next` and the
# ambiguity goes away. The leftmost pass stays as the fallback, since preferring
# a boundary can walk past the only occurrence a later letter needed.
_tui_action_scan() {
    local needle="$1" hay="$2" boundary="$3"
    local n=${#needle} h=${#hay}
    local ni=0 hi=0 start=-1 last=-1 bonus=0 c j hit
    (( n == 0 )) && { printf '0 0 0'; return 0; }
    while (( ni < n )); do
        c="${needle:$ni:1}"
        hit=-1
        if (( boundary == 1 )); then
            for (( j = hi; j < h; j++ )); do
                [[ "${hay:$j:1}" == "$c" ]] || continue
                _tui_action_boundary "$hay" "$j" || continue
                hit=$j; break
            done
        fi
        if (( hit < 0 )); then
            for (( j = hi; j < h; j++ )); do
                [[ "${hay:$j:1}" == "$c" ]] && { hit=$j; break; }
            done
        fi
        (( hit < 0 )) && return 1
        (( start < 0 )) && start=$hit
        _tui_action_boundary "$hay" "$hit" && bonus=$(( bonus + 1 ))
        last=$hit; hi=$(( hit + 1 )); ni=$(( ni + 1 ))
    done
    printf '%d %d %d' "$bonus" "$start" $(( last - start + 1 ))
}

# The better of the two passes, or a non-zero status when neither matched.
# Better is more letters on a word start, then a tighter run, then an earlier
# one, which is the order somebody reading the list would rank them in.
_tui_action_fuzzy() {
    local a b
    a="$(_tui_action_scan "$1" "$2" 1)" || a=""
    b="$(_tui_action_scan "$1" "$2" 0)" || b=""
    [[ -n "$a" ]] || { [[ -n "$b" ]] || return 1; printf '%s' "$b"; return 0; }
    [[ -n "$b" ]] || { printf '%s' "$a"; return 0; }
    local ab="${a%% *}" bb="${b%% *}"
    if (( ab > bb )); then printf '%s' "$a"; return 0; fi
    if (( bb > ab )); then printf '%s' "$b"; return 0; fi
    local as="${a##* }" bs="${b##* }"
    if (( as <= bs )); then printf '%s' "$a"; else printf '%s' "$b"; fi
}

#[pub]
# The actions whose id or label matches, best first, one id per line. An empty
# query matches everything, which is the palette on the frame it opens.
#
# Ranked by how many of the letters began a word, then by how tightly the run
# sat together, then by how early it started. Ties keep the order they were
# registered in, which is the order the caller thought they went in.
# Usage: tui_action_search <query>
tui_action_search() {
    local q="${1:-}" i hay r bonus start span
    q="$(printf '%s' "$q" | tr '[:upper:]' '[:lower:]')"
    {
        for i in "${!TUI_ACTION_ID[@]}"; do
            hay="$(printf '%s %s' "${TUI_ACTION_ID[$i]}" "${TUI_ACTION_LABEL[$i]}" \
                   | tr '[:upper:]' '[:lower:]')"
            r="$(_tui_action_fuzzy "$q" "$hay")" || continue
            bonus="${r%% *}"; start="${r#* }"; span="${start##* }"; start="${start%% *}"
            printf '%06d %06d %06d %06d %s\n' \
                $(( 999999 - bonus )) "$span" "$start" "$i" "${TUI_ACTION_ID[$i]}"
        done
    } | sort | while read -r _ _ _ _ id; do printf '%s\n' "$id"; done
}

#[pub]
# Run one, by id. Fails when the action does not exist or carries no handler,
# which is the honest answer: an action the owner dispatches itself has nothing
# here to call, and pretending otherwise would make a palette look like it ran
# something.
# Usage: tui_action_run <id> [args...]
tui_action_run() {
    local id="${1:-}" fn
    shift || true
    fn="$(tui_action_handler "$id")" || {
        printf 'tui_action_run: no action called %s\n' "${id:-empty}" >&2; return 1; }
    [[ -n "$fn" ]] || {
        printf 'tui_action_run: %s has no handler\n' "$id" >&2; return 1; }
    declare -F "$fn" >/dev/null 2>&1 || {
        printf 'tui_action_run: %s names %s, which is not defined\n' "$id" "$fn" >&2
        return 1; }
    "$fn" "$@"
}

# -----------------------------------------------------------------------------
# A keymap on disk
# -----------------------------------------------------------------------------

#[pub]
# Point actions at different keys, from a `[keys]` section in a toml file.
#
#   [keys]
#   section-next = "ctrl-down"
#   section-prev = "ctrl-up"
#   menu-back    = "q esc"
#
# An id on the left, the keys on the right, space separated, and an empty value
# unbinds the action without removing it, so it stays reachable by name.
#
# **An id nobody registered is reported and skipped rather than ignored.** A
# keymap is written by hand, so a typo is the ordinary case, and the failure it
# would otherwise produce is a key that quietly keeps doing what it did before
# with nothing anywhere saying why. The rest of the file still applies: one bad
# line should not cost somebody every binding they wrote.
#
# Returns non-zero when any line was refused, so a caller can say so once.
# Usage: tui_action_keymap <file>
tui_action_keymap() {
    local file="${1:-}" line id keys rc=0
    [[ -r "$file" ]] || {
        printf 'tui_action_keymap: cannot read %s\n' "${file:-empty}" >&2; return 1; }
    declare -F toml_section_pairs >/dev/null 2>&1 || use toml
    while IFS= read -r line; do
        id="${line%%=*}"; keys="${line#*=}"
        [[ -n "$id" ]] || continue
        if ! _tui_action_index "$id" >/dev/null; then
            printf 'tui_action_keymap: %s: no action called %s\n' "$file" "$id" >&2
            rc=1; continue
        fi
        tui_action_bind "$id" "$keys"
    done < <(toml_section_pairs "$file" keys)
    # After a rebind, a collision is the thing somebody wants told about: the
    # first action wins, the second key does nothing, and a keymap that half
    # works is worse to debug than one that does not.
    local clash
    while IFS= read -r clash; do
        [[ -n "$clash" ]] || continue
        printf 'tui_action_keymap: %s: two actions answer to one key: %s\n' \
            "$file" "$clash" >&2
        rc=1
    done < <(tui_action_conflicts)
    return $rc
}
