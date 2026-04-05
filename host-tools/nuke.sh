#!/bin/bash
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# --- Colours & helpers -------------------------------------------------------
bold=$'\033[1m'
dim=$'\033[2m'
green=$'\033[32m'
yellow=$'\033[33m'
red=$'\033[31m'
cyan=$'\033[36m'
reset=$'\033[0m'

section() { printf '\n%s=== %s ===%s\n' "$bold$cyan" "$1" "$reset"; }
warn()    { printf '  %s⚠  %s%s\n' "$yellow" "$1" "$reset"; }
ok()      { printf '  %s✓  %s%s\n' "$green" "$1" "$reset"; }
err()     { printf '  %s✗  %s%s\n' "$red" "$1" "$reset"; }

ask_yes_no() {
    local prompt="$1"
    local answer
    printf '  %s [y/N] ' "$prompt"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# --- Inventory what will be destroyed ----------------------------------------
section "The following will be destroyed"

# Container
CONTAINER_ID=$(docker ps -aq --filter "label=devcontainer.local_folder=$PROJ_DIR" 2>/dev/null || true)
if [ -n "$CONTAINER_ID" ]; then
    state=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_ID" 2>/dev/null || echo "unknown")
    printf '  Container:  %s (%s)\n' "${CONTAINER_ID:0:12}" "$state"
else
    printf '  Container:  %snone found%s\n' "$dim" "$reset"
fi

# Ephemeral volume (ccache)
vol="nss-dev-ccache"
info=$(docker volume inspect "$vol" --format '{{.CreatedAt}}' 2>/dev/null || true)
if [ -n "$info" ]; then
    printf '  Volume:     %s  %s(created: %s)%s\n' "$vol" "$dim" "$info" "$reset"
else
    printf '  Volume:     %s  %snot found%s\n' "$vol" "$dim" "$reset"
fi

# Source volumes (nss, nspr, worktrees) — shown but handled separately
section "Source volumes (prompted separately)"
for vol in nss-dev-nss nss-dev-nspr nss-dev-worktrees; do
    info=$(docker volume inspect "$vol" --format '{{.CreatedAt}}' 2>/dev/null || true)
    if [ -n "$info" ]; then
        printf '  Volume:     %s  %s(created: %s)%s\n' "$vol" "$dim" "$info" "$reset"
    else
        printf '  Volume:     %s  %snot found%s\n' "$vol" "$dim" "$reset"
    fi
done

host_nss_dir="$PROJ_DIR/host-nss"

# Exchange repo
exchange_dir="$PROJ_DIR/.nss-exchange.git"
if [ -d "$exchange_dir" ]; then
    exchange_size=$(du -sh "$exchange_dir" 2>/dev/null | cut -f1 || echo "?")
    exchange_branches=$(git --git-dir="$exchange_dir" branch 2>/dev/null | wc -l)
    printf '  exchange:   %s, %s branch(es)\n' "$exchange_size" "$exchange_branches"

    # Warn about exchange commits not yet in host-nss
    if [ -d "$host_nss_dir/.git" ] && [ "$exchange_branches" -gt 0 ]; then
        unfetched=""
        while IFS= read -r ref; do
            [ -z "$ref" ] && continue
            branch="${ref##*/}"
            commit=$(git --git-dir="$exchange_dir" rev-parse "$ref" 2>/dev/null || continue)
            if ! git -C "$host_nss_dir" cat-file -e "$commit" 2>/dev/null; then
                summary=$(git --git-dir="$exchange_dir" log -1 --format='%h %s' "$ref" 2>/dev/null || echo "")
                unfetched="${unfetched}    ${bold}${branch}${reset}  ${summary}\n"
            fi
        done < <(git --git-dir="$exchange_dir" for-each-ref --format='%(refname)' refs/heads/)

        if [ -n "$unfetched" ]; then
            echo ""
            warn "Exchange branches not yet in host-nss (will be lost):"
            printf '%b' "$unfetched"
        fi
    fi
else
    printf '  exchange:   %snot found%s\n' "$dim" "$reset"
fi

bugs_dir="$PROJ_DIR/bugs"

# --- Confirm -----------------------------------------------------------------
echo ""
printf '%s%sThis will permanently delete the container, ccache volume, and exchange repo.%s\n' "$bold" "$red" "$reset"
printf 'Type "nuke" to confirm: '
read -r confirm

if [ "$confirm" != "nuke" ]; then
    echo "Aborted."
    exit 1
fi

echo ""

# --- Destroy container -------------------------------------------------------
section "Removing container"

if [ -n "$CONTAINER_ID" ]; then
    docker rm -f "$CONTAINER_ID" >/dev/null 2>&1
    ok "Container removed"
else
    ok "No container to remove"
fi

# --- Destroy ccache volume ---------------------------------------------------
section "Removing ccache volume"

if docker volume rm nss-dev-ccache >/dev/null 2>&1; then
    ok "Removed nss-dev-ccache"
else
    ok "nss-dev-ccache already absent"
fi

# --- Reset exchange repo -----------------------------------------------------
section "Resetting exchange repo"

if [ -d "$exchange_dir" ]; then
    rm -rf "$exchange_dir"
    git init --bare "$exchange_dir" >/dev/null 2>&1
    ok "Exchange repo reset"
else
    git init --bare "$exchange_dir" >/dev/null 2>&1
    ok "Exchange repo created"
fi

# --- Optionally wipe source volumes (nss, nspr, worktrees) ------------------
section "Source volumes (nss, nspr, worktrees)"

source_vols_exist=false
for vol in nss-dev-nss nss-dev-nspr nss-dev-worktrees; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        source_vols_exist=true
        break
    fi
done

if $source_vols_exist; then
    printf '  These volumes hold your NSS/NSPR checkouts and worktrees.\n'
    printf '  They take a while to re-clone if deleted.\n\n'
    if ask_yes_no "Wipe source volumes (nss, nspr, worktrees)?"; then
        for vol in nss-dev-nss nss-dev-nspr nss-dev-worktrees; do
            if docker volume rm "$vol" >/dev/null 2>&1; then
                ok "Removed $vol"
            else
                ok "$vol already absent"
            fi
        done
    else
        ok "Source volumes kept"
    fi
else
    ok "No source volumes present"
fi

# --- Optionally wipe bugs/ --------------------------------------------------
section "Bug data"

if [ -d "$bugs_dir" ]; then
    # Match both new-style (1234567-slug/) and legacy (bug-1234567/) folders
    bug_count=$(find "$bugs_dir" -maxdepth 1 -type d \( -regex '.*/[0-9].*' -o -name 'bug-*' \) 2>/dev/null | wc -l)
    if [ "$bug_count" -gt 0 ]; then
        bugs_size=$(du -sh "$bugs_dir" 2>/dev/null | cut -f1 || echo "?")
        printf '  %s bug(s), %s total:\n' "$bug_count" "$bugs_size"
        find "$bugs_dir" -maxdepth 1 -type d \( -regex '.*/[0-9].*' -o -name 'bug-*' \) -printf '%f\n' 2>/dev/null | sort | while IFS= read -r bug; do
            printf '    %s\n' "$bug"
        done
        echo ""
        if ask_yes_no "Wipe bugs/?"; then
            rm -rf "$bugs_dir"
            mkdir -p "$bugs_dir"
            ok "bugs/ wiped"
        else
            ok "bugs/ kept"
        fi
    else
        ok "bugs/ is empty"
    fi
else
    ok "bugs/ not present"
fi

# --- Optionally wipe host-nss/ ----------------------------------------------
section "Host NSS repo"

if [ -d "$host_nss_dir/.git" ]; then
    # Find branches not merged to upstream
    local_branches=()
    while IFS= read -r branch; do
        [ -z "$branch" ] && continue
        [[ "$branch" == *"HEAD"* ]] && continue
        local_branches+=("$branch")
    done < <(git -C "$host_nss_dir" branch --no-merged origin/HEAD 2>/dev/null || true)

    if [ ${#local_branches[@]} -gt 0 ]; then
        warn "Unmerged branches:"
        for branch in "${local_branches[@]}"; do
            last_commit=$(git -C "$host_nss_dir" log -1 --format='%h %s' "$branch" 2>/dev/null || echo "")
            printf '    %s%-20s%s  %s\n' "$bold" "$branch" "$reset" "$last_commit"
        done
        echo ""
    else
        printf '  %sNo unmerged branches%s\n' "$dim" "$reset"
    fi

    if ask_yes_no "Wipe host-nss/?"; then
        rm -rf "$host_nss_dir"
        ok "host-nss/ removed"
    else
        ok "host-nss/ kept"
    fi
else
    ok "host-nss/ not present"
fi

echo ""
ok "Nuke complete."
echo ""
