#!/usr/bin/env bash
# Configure before USB enumeration. No requests are sent to the phone.
set -euo pipefail

quirks_file=/sys/module/usbcore/parameters/quirks
state_dir=/run/lgv30-fastboot-lpm

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

# Preserve other device entries and any existing flags for this VID:PID.
with_no_lpm() {
    local entry vid pid flags extra result='' found=0
    local -a entries=()
    IFS=, read -r -a entries <<< "$1"
    for entry in "${entries[@]}"; do
        IFS=: read -r vid pid flags extra <<< "$entry"
        if [[ ${vid,,} == 18d1 && ${pid,,} == d00d ]]; then
            [[ $flags == *k* ]] || entry="${entry}k"
            found=1
        fi
        result+="${result:+,}${entry}"
    done
    [[ $found == 1 ]] || result+="${result:+,}18d1:d00d:k"
    printf '%s\n' "$result"
}

apply_fix() {
    local current desired
    [[ -w $quirks_file ]] || die "Cannot write $quirks_file"
    current=$(<"$quirks_file")
    desired=$(with_no_lpm "$current")
    if [[ -d $state_dir ]]; then
        [[ -f $state_dir/quirks.before && -f $state_dir/quirks.applied ]] || die 'Incomplete saved state; use PC reboot to reset.'
        [[ $current == "$(<"$state_dir/quirks.applied")" ]] || die 'USB quirks changed since setup; leaving them untouched.'
    else
        (umask 077; mkdir -- "$state_dir")
        printf '%s\n' "$current" > "$state_dir/quirks.before"
        printf '%s\n' "$desired" > "$state_dir/quirks.applied"
    fi
    if [[ $current != "$desired" ]]; then
        printf '%s\n' "$desired" > "$quirks_file"
    fi
    printf 'usbcore quirks: %s\n' "$(<"$quirks_file")"
    printf '%s\n' 'LPM workaround configured for 18d1:d00d.' \
        'Now connect/reconnect the phone and enter fastboot.' \
        'The setting expires at PC reboot. No phone data was changed.'
}

restore_fix() {
    local current before applied
    [[ -d $state_dir ]] || die 'No saved setting from this script in the current PC boot.'
    [[ -f $state_dir/quirks.before && -f $state_dir/quirks.applied ]] || die 'Incomplete saved state; use PC reboot to reset.'
    current=$(<"$quirks_file")
    before=$(<"$state_dir/quirks.before")
    applied=$(<"$state_dir/quirks.applied")
    [[ $current == "$applied" || $current == "$before" ]] || die 'USB quirks changed since setup; refusing to overwrite them. PC reboot resets temporary settings.'
    if [[ $current != "$before" ]]; then
        printf '%s\n' "$before" > "$quirks_file"
    fi
    unlink -- "$state_dir/quirks.before"
    unlink -- "$state_dir/quirks.applied"
    rmdir -- "$state_dir"
    printf '%s\n' 'Previous USB quirks restored. Reconnect the phone for this to take effect.'
}

main() {
    [[ $# -le 1 ]] || die 'Usage: fix-fastboot.sh [apply|status|restore]'
    [[ -r $quirks_file ]] || die 'Linux usbcore quirks interface is unavailable.'
    case ${1:-apply} in
        apply|restore)
            [[ $EUID == 0 ]] || die "Run: sudo bash $0 ${1:-apply}"
            if [[ ${1:-apply} == apply ]]; then apply_fix; else restore_fix; fi
            ;;
        status)
            printf 'usbcore quirks: %s\n' "$(<"$quirks_file")"
            printf '%s\n' 'Expected entry: 18d1:d00d:k (or k added to existing flags).'
            ;;
        *) die 'Usage: fix-fastboot.sh [apply|status|restore]' ;;
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
