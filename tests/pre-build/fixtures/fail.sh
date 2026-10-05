#!/usr/bin/env bash
# Pre-build fixture: a script that fails must stop the workflow.
# The marker lets the self-test tell "the script ran and failed" from "the validator refused it".
touch ran-and-failed
echo "pre-build fixture: failing on purpose" >&2
exit 7
