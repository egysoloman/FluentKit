# Maintained quality checks

Run `./tools/run-quality-checks.sh [output-directory]` from any working directory. CI uses this
fixed entry point. It runs the Release work-count/editing/appearance probes, mounts registered
Gallery samples in light/dark/RTL environments, captures controlled visual states, and checks the
JSON results and collection diagnostics. It does not replace `swift test` or real interaction QA.
MenuPointerAudit covers 64 native tracking scenarios across themes, directions and contrast modes,
including delayed close, descendant handoff, sibling replacement and expanded-row rendering.
MenuBarInteractionAudit covers 36 theme/direction/input cases, including top-level handoff,
cancelled press/hover, access keys and repeated opening commands.

CI also captures `swift test` output and runs `tools/check_test_diagnostics.py <log>` to reject
AppKit constraint conflicts even when XCTest passes. `-warnings-as-errors` only promotes compiler
warnings; it does not catch these runtime layout diagnostics. Preserve the test process exit status
with `set -o pipefail` when recording its output through `tee`.

The Swift probes began with the 2026-10-30 audit and now live here for ongoing maintenance.
Historical reports, one-off probes and raw evidence are local-only; they are not required to
run these checks. Add or change a maintained probe here and update the gate explicitly.

The default output and build directories are under the system temporary directory, so running the
checks does not add generated evidence to the repository. `FLUENTKIT_QUALITY_BUILD` selects a reusable
build directory. `AUDIT_VISUAL_BASELINE` enables pixel comparison against a reviewed capture from
the same OS/build, scale and font environment (requires Pillow). Without it, images are emitted for
review and no claim of pixel agreement is made.

Both Swift Build and the earlier native SwiftPM product layouts are supported. The toolchain's
default engine is used unless `FLUENTKIT_QUALITY_BUILD_SYSTEM` is set (for example, `native` to
exercise the older layout with a newer toolchain). Use separate build directories for each engine.
