# Maintained quality checks

Run `./tools/run-quality-checks.sh [output-directory]` from any working directory. CI uses this
fixed entry point. It runs the Release work-count/editing/appearance probes, mounts registered
Gallery samples in light/dark/RTL environments, captures controlled visual states, and checks the
JSON results and collection diagnostics. It does not replace `swift test` or real interaction QA.

CI also captures `swift test` output and runs `tools/check_test_diagnostics.py <log>` to reject
AppKit constraint conflicts even when XCTest passes. `-warnings-as-errors` only promotes compiler
warnings; it does not catch these runtime layout diagnostics. Preserve the test process exit status
with `set -o pipefail` when recording its output through `tee`.

The Swift probes began with the 2026-10-30 audit and now live here for ongoing maintenance.
`audits/<date>/` keeps its original probe versions and raw evidence; CI never discovers a probe
by choosing the latest date. Add or change a maintained probe here and update the gate explicitly.

The default output and build directories are under the system temporary directory, so running the
checks does not overwrite committed historical results. `FLUENTKIT_QUALITY_BUILD` selects a reusable
build directory. `AUDIT_VISUAL_BASELINE` enables pixel comparison against a reviewed capture from
the same OS/build, scale and font environment (requires Pillow). Without it, images are emitted for
review and no claim of pixel agreement is made.
