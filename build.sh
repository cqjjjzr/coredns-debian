#!/bin/sh
set -eu

usage() {
    cat <<'HELP'
Usage: ./build.sh [--source DIR | --tag TAG] [--repo URL] [--output DIR]

  --source DIR  Build a copy of an existing CoreDNS source directory.
  --tag TAG     Clone this release tag; defaults to the latest stable tag.
  --repo URL    Git repository (default: https://github.com/coredns/coredns.git).
  --output DIR  Package output directory (default: ./build).

Requires Git, Go, build-essential, debhelper, and ca-certificates on Debian.
The Go toolchain is selected by CoreDNS's .go-version file.
HELP
}

source_dir=
tag=
repo=https://github.com/coredns/coredns.git
output_dir=./build
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --source|--tag|--repo|--output)
            [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
            [ -n "$2" ] || { echo "Empty value for $1" >&2; exit 2; }
            case "$1" in
                --source) source_dir=$2 ;;
                --tag) tag=$2 ;;
                --repo) repo=$2 ;;
                --output) output_dir=$2 ;;
            esac
            shift 2 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done
[ -z "$source_dir" ] || [ -z "$tag" ] || {
    echo "Use either --source or --tag." >&2; exit 2;
}
for command in git go dpkg-buildpackage dh; do
    command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done
packaging_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -n "$source_dir" ]; then
    source_dir=$(CDPATH= cd -- "$source_dir" && pwd)
    [ -f "$source_dir/coremain/version.go" ] || { echo "Not a CoreDNS source directory: $source_dir" >&2; exit 1; }
fi
mkdir -p -- "$output_dir"
output_dir=$(CDPATH= cd -- "$output_dir" && pwd)
# Keep the temporary copy outside the input tree, even when output is inside it.
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT HUP INT TERM
mkdir "$work_dir/coredns"
if [ -n "$source_dir" ]; then
    tar -C "$source_dir" --exclude='./.git' --exclude='./debian' \
        --exclude='./build' --exclude='./coredns' -cf "$work_dir/source.tar" .
    tar -C "$work_dir/coredns" -xf "$work_dir/source.tar"
    GITCOMMIT=$(git -C "$source_dir" describe --tags --always --dirty 2>/dev/null || echo unknown)
else
    if [ -z "$tag" ]; then
        git ls-remote --tags --refs "$repo" > "$work_dir/tags"
        tag=$(sed -n 's@.*refs/tags/\(v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$@\1@p' "$work_dir/tags" | sort -V | tail -n 1)
        [ -n "$tag" ] || { echo "No stable release tags found in $repo" >&2; exit 1; }
    fi
    git clone --depth 1 --branch "$tag" --single-branch -- "$repo" "$work_dir/coredns"
    git -C "$work_dir/coredns" checkout --detach "refs/tags/$tag"
    GITCOMMIT=$(git -C "$work_dir/coredns" describe --tags --always)
fi
export GITCOMMIT
rm -rf -- "$work_dir/coredns/debian"
cp -a "$packaging_dir/debian" "$work_dir/coredns/debian"
cd "$work_dir/coredns"
version=$(sed -n 's/^[[:space:]]*CoreVersion[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' coremain/version.go)
[ -n "$version" ] || { echo "Cannot read CoreDNS version." >&2; exit 1; }
release_notes="notes/coredns-$version.md"
if [ -s "$release_notes" ]; then
    awk '
        /^\+\+\+$/ { metadata = !metadata; next }
        metadata { next }
        /^## / {
            section = 1
            changes = ($0 == "## Noteworthy Changes")
            paragraph = 0
            next
        }
        section && !changes { next }
        /^[[:space:]]*$/ { paragraph = 0; next }
        {
            sub(/^[[:space:]]*[*-][[:space:]]+/, "")
            print (changes || !paragraph ? "  * " : "    ") $0
            paragraph = 1
        }
    ' "$release_notes" > "$work_dir/changes"
fi
if [ ! -s "$work_dir/changes" ]; then
    cp "$packaging_dir/debian/changelog" "$work_dir/changes"
fi
maintainer=$(sed -n 's/^Maintainer: //p' debian/control)
{
    printf 'coredns (%s-1) unstable; urgency=medium\n\n' "$version"
    cat "$work_dir/changes"
    printf '\n -- %s  %s\n' "$maintainer" "$(LC_ALL=C date -R)"
} > debian/changelog
printf 'Building CoreDNS %s (%s)\n' "$version" "$GITCOMMIT"
dpkg-buildpackage -us -uc -b
cp "$work_dir"/coredns_*.deb "$work_dir"/coredns_*.buildinfo "$work_dir"/coredns_*.changes "$output_dir/"
printf 'Packages written to %s\n' "$output_dir"
