# Releasing FluentKit

The version in `VERSION`, the dated changelog heading, the Git tag and the GitHub Release must
match. Use Semantic Versioning; document additions, behavior changes and remaining limitations.

## Prepare and validate

1. Move completed entries from `Unreleased` into the new dated version section in `CHANGELOG.md`.
2. Update `VERSION` and the installation example in `README.md`.
3. Run the required gates from the intended release tree:

   ```bash
   swift build -Xswiftc -warnings-as-errors
   swift test -Xswiftc -warnings-as-errors
   swift build --configuration release -Xswiftc -warnings-as-errors
   ./tools/run-quality-checks.sh
   ```

   Run `swift run FluentKitValidation` in an interactive macOS session. For control, layout,
   navigation or motion changes, also build the standalone Xcode Gallery and inspect relevant
   renders according to [SNAPSHOT_BASELINES.md](SNAPSHOT_BASELINES.md). Record the actual platform
   and validation scope; automated checks do not establish Windows parity or physical input QA.

4. Commit and push the preparation changes. Wait for CI on that exact `main` commit to succeed.
5. Prepare concise release notes covering user-visible changes, compatibility and known limits.
   Store temporary notes and raw validation output outside the checkout. Do not attach audit
   reports, screenshot batches or logs as release assets.

## Publish

Create an annotated tag from the validated commit, then publish the release:

```bash
RELEASE_VERSION="$(cat VERSION)"
git tag -a "v$RELEASE_VERSION" -m "FluentKit $RELEASE_VERSION"
git push origin "v$RELEASE_VERSION"
gh release create "v$RELEASE_VERSION" --verify-tag --latest \
  --title "FluentKit $RELEASE_VERSION" --notes-file /tmp/fluentkit-release-notes.md
```

Confirm the remote tag resolves to the validated commit and the published release uses that tag.
Stable releases should not be marked as prereleases. Do not move an existing published tag;
follow-up fixes belong in a new version.
