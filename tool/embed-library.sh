#!/bin/bash
# Writes `lib/Forge.yaml`, Forge's library, into a Swift source, so the
# grammar a workflow leans on arrives with the binary rather than off a disk
# the daemon may not have.
#
# The document is the source; this is a copy of it. `ForgeVocabularyTests` holds
# the two to being the same text, so a library edited without running this
# is a red test.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
library="$root/lib/Forge.yaml"
written="$root/package/Sources/Forge/Service/Host/Vocabulary/Library.swift"

{
    echo "//"
    echo "//  Library.swift"
    echo "//  Forge"
    echo "//"
    echo "//  Written by tool/embed-library.sh. Edit lib/Forge.yaml and run it again."
    echo "//"
    echo ""
    echo "import Foundation"
    echo ""
    echo "// The text of \`lib/Forge.yaml\`, as it stands in the repository."
    echo "enum Library {"
    echo "    static let text = \"\"\""
    /usr/bin/sed -e 's/\\/\\\\/g' -e 's/"""/\\"\\"\\"/g' -e 's/^/        /' "$library"
    echo "        \"\"\""
    echo "}"
} > "$written"

echo "$written"
