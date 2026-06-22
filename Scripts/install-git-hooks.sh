#!/bin/sh
set -e
root=$(git rev-parse --show-toplevel)
cd "$root"
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
echo "Installed git hooks from .githooks/"
