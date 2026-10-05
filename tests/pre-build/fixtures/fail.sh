#!/usr/bin/env bash
# Pre-build fixture: a script that fails must stop the workflow.
echo "pre-build fixture: failing on purpose" >&2
exit 7
