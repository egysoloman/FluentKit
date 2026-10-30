# Fixed CI quality entry point

CI and current contributor instructions now call `tools/run-quality-checks.sh`. Its six maintained
Swift probes live under `tools/quality/`. Historical dated scripts and evidence are unchanged; no
"latest audit directory" heuristic decides what CI tests.

Validated from `/tmp`, outside the repository, with the output path `/tmp/fluentkit quality entry`.
Release compilation (warnings as errors), all six probes, deterministic JSON/diagnostic gates and
the existing light/dark pixel comparison passed. Raw JSON, diagnostics and comparison results are
preserved beside this note. This change does not alter runtime code. Unit tests were not rerun for
this entry-point change; the preceding collection-layout repair passed the full 135-test suite.

Output and build products default to the system temporary directory. An explicit output directory,
`FLUENTKIT_QUALITY_BUILD`, and `AUDIT_VISUAL_BASELINE` support artifact collection, cache reuse and
reviewed same-environment pixel comparisons. CI always runs the deterministic gates; pixels remain
an explicitly enabled same-environment check.
