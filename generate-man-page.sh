set -o errexit

swift build -c release
echo "[AUTHOR]

@Samasaur1 on GitHub" > author.inc
help2man -i author.inc -o solver.1 -N .build/release/solver
rm author.inc
