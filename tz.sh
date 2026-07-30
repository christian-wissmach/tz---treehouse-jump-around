# tz.sh - treehouse-aware directory jumper with relative path ranking
# Based on z.sh by rupa deadwyler (WTFPL license, Version 2)
#
# Maintains a jump-list of directories by relative paths within treehouse
# worktrees. A single datafile is shared across all worktrees, so your
# navigation habits transfer when you switch between them.
#
# INSTALL:
#     * source this file in your .bashrc/.zshrc:
#         . /path/to/tz.sh
#     * cd around within treehouse worktrees to build up the db
#
# CONFIGURE:
#     * set $_TZ_CMD to change the command name (default: tz)
#     * set $_TZ_DATA to change the datafile (default: ~/.tz)
#     * set $_TZ_ROOT_FILE to change the root cache (default: ~/.tz_root)
#     * set $_TZ_MAX_SCORE lower to age entries out faster (default: 9000)
#     * set $_TZ_NO_RESOLVE_SYMLINKS to prevent symlink resolution
#     * set $_TZ_NO_PROMPT_COMMAND if you're handling PROMPT_COMMAND yourself
#     * set $_TZ_EXCLUDE_DIRS to an array of relative dirs to exclude
#
# USE:
#     * tz         # list all entries with ranks
#     * tz .       # cd to treehouse root
#     * tz foo     # cd to most frecent dir matching foo
#     * tz foo bar # cd to most frecent dir matching foo and bar
#     * tz -r foo  # cd to highest ranked dir matching foo
#     * tz -t foo  # cd to most recently accessed dir matching foo
#     * tz -l foo  # list matches instead of cd
#     * tz -e foo  # echo the best match, don't cd
#     * tz -e .    # echo the treehouse root
#     * tz -c foo  # restrict matches to subdirs of $PWD
#     * tz -x      # remove the current directory from the datafile
#     * tz -h      # show a brief help message

[ -d "${_TZ_DATA:-$HOME/.tz}" ] && {
    echo "ERROR: tz.sh's datafile (${_TZ_DATA:-$HOME/.tz}) is a directory."
}

_tz() {

    local datafile="${_TZ_DATA:-$HOME/.tz}"
    local rootfile="${_TZ_ROOT_FILE:-$HOME/.tz_root}"

    # if symlink, dereference
    [ -h "$datafile" ] && datafile=$(readlink "$datafile")

    # bail if we don't own datafile and $_TZ_OWNER not set
    [ -z "$_TZ_OWNER" -a -f "$datafile" -a ! -O "$datafile" ] && return

    # --- helper functions ---

    _tz_get_root() {
        [ -f "$rootfile" ] && \cat "$rootfile" 2>/dev/null
    }

    _tz_set_root() {
        printf '%s' "$1" > "$rootfile"
    }

    _tz_detect_root() {
        # Run 'treehouse status' and extract the "you're here" worktree path
        local status_output
        status_output=$(treehouse status 2>&1) || return 1
        local root
        root=$(printf '%s\n' "$status_output" | \awk '/you'\''re here/ { print $NF }')
        if [ -n "$root" ]; then
            # expand ~ to $HOME
            case "$root" in
                "~/"*) root="$HOME/${root#"~/"}";;
                "~")   root="$HOME";;
            esac
            printf '%s' "$root"
            return 0
        fi
        return 1
    }

    _tz_relpath() {
        # Strip root prefix from an absolute path; "." for the root itself
        local abspath="$1" root="$2"
        local rel="${abspath#"$root"}"
        rel="${rel#/}"
        [ -z "$rel" ] && rel="."
        printf '%s' "$rel"
    }

    _tz_all_entries() {
        # Every entry in the datafile (preserves cross-worktree data)
        [ -f "$datafile" ] || return
        \cat "$datafile"
    }

    _tz_valid_dirs() {
        # Only entries whose relative path exists under the given root
        [ -f "$datafile" ] || return
        local line root="$1"
        while IFS= read -r line; do
            local relpath="${line%%\|*}"
            local fullpath
            if [ "$relpath" = "." ]; then
                fullpath="$root"
            else
                fullpath="$root/$relpath"
            fi
            [ -d "$fullpath" ] && echo "$line"
        done < "$datafile"
    }

    # --- main logic ---

    # add entries (called from precmd hook)
    if [ "$1" = "--add" ]; then
        shift
        local abspath="$*"

        # get cached root; silently skip when unavailable or mismatched
        # (never call treehouse status from precmd — too expensive)
        local root
        root=$(_tz_get_root)
        [ -n "$root" ] || return
        case "$abspath" in
            "$root"*) ;;
            *) return;;
        esac

        # compute relative path
        local relpath
        relpath=$(_tz_relpath "$abspath" "$root")

        # honour exclude list
        if [ ${#_TZ_EXCLUDE_DIRS[@]} -gt 0 ]; then
            local exclude
            for exclude in "${_TZ_EXCLUDE_DIRS[@]}"; do
                case "$relpath" in "$exclude"*) return;; esac
            done
        fi

        # update the datafile (keep ALL entries so other worktrees keep theirs)
        local tempfile="$datafile.$RANDOM"
        local score=${_TZ_MAX_SCORE:-9000}
        _tz_all_entries | \awk -v path="$relpath" -v now="$(\date +%s)" -v score=$score -F"|" '
            BEGIN {
                rank[path] = 1
                time[path] = now
            }
            $2 >= 1 {
                if( $1 == path ) {
                    rank[$1] = $2 + 1
                    time[$1] = now
                } else {
                    rank[$1] = $2
                    time[$1] = $3
                }
                count += $2
            }
            END {
                if( count > score ) {
                    for( x in rank ) print x "|" 0.99*rank[x] "|" time[x]
                } else for( x in rank ) print x "|" rank[x] "|" time[x]
            }
        ' 2>/dev/null >| "$tempfile"
        if [ $? -ne 0 -a -f "$datafile" ]; then
            \env rm -f "$tempfile"
        else
            [ "$_TZ_OWNER" ] && chown $_TZ_OWNER:"$(id -ng $_TZ_OWNER)" "$tempfile"
            \env mv -f "$tempfile" "$datafile" || \env rm -f "$tempfile"
        fi

    # tab completion
    elif [ "$1" = "--complete" -a -s "$datafile" ]; then
        local root
        root=$(_tz_get_root)
        [ -n "$root" ] || return

        _tz_valid_dirs "$root" | \awk -v q="$2" -F"|" '
            BEGIN {
                q = substr(q, 3)
                if( q == tolower(q) ) imatch = 1
                gsub(/ /, ".*", q)
            }
            {
                if( imatch ) {
                    if( tolower($1) ~ q ) print $1
                } else if( $1 ~ q ) print $1
            }
        ' 2>/dev/null

    else
        # --- ensure we have a valid root ---
        local root
        root=$(_tz_get_root)

        local need_update=0
        if [ -z "$root" ]; then
            need_update=1
        else
            case "$PWD" in
                "$root"*) ;;
                *) need_update=1;;
            esac
        fi

        if [ $need_update -eq 1 ]; then
            local detected
            detected=$(_tz_detect_root)
            if [ -n "$detected" ]; then
                _tz_set_root "$detected"
                root="$detected"
            else
                # not in a treehouse — offer to jump back to cached scope
                if [ -n "$root" ] && [ -d "$root" ]; then
                    echo "Not in a treehouse." >&2
                    printf "Jump back to treehouse scope (%s)? [y/N] " "$root" >&2
                    local answer
                    read -r answer
                    case "$answer" in
                        [Yy]*)
                            # keep cached root, fall through to process query
                            ;;
                        *)
                            _tz_set_root ""
                            return 1
                            ;;
                    esac
                else
                    echo "Not in a treehouse and no previous root available." >&2
                    return 1
                fi
            fi
        fi

        # current dir as a relative path (used by -c and -x)
        local currel
        currel=$(_tz_relpath "$PWD" "$root")

        local echo fnd last list opt typ
        while [ "$1" ]; do case "$1" in
            --) while [ "$1" ]; do shift; fnd="$fnd${fnd:+ }$1"; done;;
            -*) opt=${1:1}; while [ "$opt" ]; do case ${opt:0:1} in
                    c) [ "$currel" != "." ] && fnd="^$currel/ $fnd";;
                    e) echo=1;;
                    h) echo "${_TZ_CMD:-tz} [-cehlrtx] args" >&2; return;;
                    l) list=1;;
                    r) typ="rank";;
                    t) typ="recent";;
                    x) local tmpf="$datafile.$RANDOM"
                       \awk -v p="$currel" -F'|' '$1 != p' "$datafile" \
                           >| "$tmpf" \
                           && \env mv -f "$tmpf" "$datafile" \
                           || \env rm -f "$tmpf"
                       ;;
                esac; opt=${opt:1}; done;;
             *) fnd="$fnd${fnd:+ }$1";;
        esac; last=$1; [ "$#" -gt 0 ] && shift; done

        # "tz ." → go to root
        if [ "$fnd" = "." ]; then
            if [ "$echo" ]; then
                echo "$root"
            else
                builtin cd "$root"
            fi
            return
        fi

        [ "$fnd" -a "$fnd" != "^$currel/ " ] || list=1

        # no file yet
        [ -f "$datafile" ] || return

        local cd
        cd="$( < <( _tz_valid_dirs "$root" ) \awk -v t="$(\date +%s)" -v list="$list" -v typ="$typ" -v q="$fnd" -F"|" '
            function frecent(rank, time) {
                dx = t - time
                return int(10000 * rank * (3.75/((0.0001 * dx + 1) + 0.25)))
            }
            function output(matches, best_match, common) {
                if( list ) {
                    if( common ) {
                        printf "%-10s %s\n", "common:", common > "/dev/stderr"
                    }
                    cmd = "sort -n >&2"
                    for( x in matches ) {
                        if( matches[x] ) {
                            printf "%-10s %s\n", matches[x], x | cmd
                        }
                    }
                } else {
                    if( common && !typ ) best_match = common
                    print best_match
                }
            }
            function common(matches) {
                for( x in matches ) {
                    if( matches[x] && (!short || length(x) < length(short)) ) {
                        short = x
                    }
                }
                if( short == "." ) return
                for( x in matches ) if( matches[x] && index(x, short) != 1 ) {
                    return
                }
                return short
            }
            BEGIN {
                gsub(" ", ".*", q)
                hi_rank = ihi_rank = -9999999999
            }
            {
                if( typ == "rank" ) {
                    rank = $2
                } else if( typ == "recent" ) {
                    rank = $3 - t
                } else rank = frecent($2, $3)
                if( $1 ~ q ) {
                    matches[$1] = rank
                } else if( tolower($1) ~ tolower(q) ) imatches[$1] = rank
                if( matches[$1] && matches[$1] > hi_rank ) {
                    best_match = $1
                    hi_rank = matches[$1]
                } else if( imatches[$1] && imatches[$1] > ihi_rank ) {
                    ibest_match = $1
                    ihi_rank = imatches[$1]
                }
            }
            END {
                if( best_match ) {
                    output(matches, best_match, common(matches))
                    exit
                } else if( ibest_match ) {
                    output(imatches, ibest_match, common(imatches))
                    exit
                }
                exit(1)
            }
        ')"

        if [ "$?" -eq 0 ]; then
            if [ "$cd" ]; then
                local fullpath
                if [ "$cd" = "." ]; then
                    fullpath="$root"
                else
                    fullpath="$root/$cd"
                fi
                if [ "$echo" ]; then
                    echo "$fullpath"
                else
                    builtin cd "$fullpath"
                fi
            fi
        else
            return $?
        fi
    fi
}

alias ${_TZ_CMD:-tz}='_tz 2>&1'

[ "$_TZ_NO_RESOLVE_SYMLINKS" ] || _TZ_RESOLVE_SYMLINKS="-P"

if type compctl >/dev/null 2>&1; then
    # zsh
    [ "$_TZ_NO_PROMPT_COMMAND" ] || {
        if [ "$_TZ_NO_RESOLVE_SYMLINKS" ]; then
            _tz_precmd() {
                (_tz --add "${PWD:a}" &)
                : $RANDOM
            }
        else
            _tz_precmd() {
                (_tz --add "${PWD:A}" &)
                : $RANDOM
            }
        fi
        [[ -n "${precmd_functions[(r)_tz_precmd]}" ]] || {
            precmd_functions[$(($#precmd_functions+1))]=_tz_precmd
        }
    }
    _tz_zsh_tab_completion() {
        local compl
        read -l compl
        reply=(${(f)"$(_tz --complete "$compl")"})
    }
    compctl -U -K _tz_zsh_tab_completion _tz
elif type complete >/dev/null 2>&1; then
    # bash
    complete -o filenames -C '_tz --complete "$COMP_LINE"' ${_TZ_CMD:-tz}
    [ "$_TZ_NO_PROMPT_COMMAND" ] || {
        grep "_tz --add" <<< "$PROMPT_COMMAND" >/dev/null || {
            PROMPT_COMMAND="$PROMPT_COMMAND"$'\n''(_tz --add "$(command pwd '$_TZ_RESOLVE_SYMLINKS' 2>/dev/null)" 2>/dev/null &);'
        }
    }
fi
