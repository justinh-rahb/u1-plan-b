#!/bin/sh
# Guard: a `v<version>` release tag must match the version manifest.json declares, because the
# package filename and the GitHub release are stamped from the manifest, not the tag. A ref that is
# not a version tag at all is refused too: a branch never publishes.
set -eu

ref_name="${1:-}"

case "$ref_name" in
    v[0-9]*) ;;
    *)
        echo "'$ref_name' is not a v<version> tag: a release is published by a version tag and by nothing else" >&2
        exit 1
        ;;
esac

declared_version="$(jq -r '.version' manifest.json)"
if [ "${ref_name#v}" != "$declared_version" ]; then
    echo "tag '$ref_name' does not match manifest.json version $declared_version" >&2
    exit 1
fi

echo "tag '$ref_name' matches manifest.json version $declared_version"
