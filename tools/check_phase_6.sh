#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

alr build --validation -- -j1
(cd tests && alr build --validation -- -j1 && ./bin/improve_tests)
alr exec -- gprbuild -P tools/check_all.gpr -p
tools/bin/check_all
