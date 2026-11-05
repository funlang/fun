# Releasing Fun

Maintainer checklist for cutting a release.

**English** (this file) · [简体中文](RELEASING.zh.md)

## 1. Prepare

- Make sure the regression workflow is green on `main`.
- Move the `Unreleased` entries in `CHANGELOG.md` and `CHANGELOG.zh.md` under the new version with today's date.
- Update `ROADMAP.md`: baseline version, regression/loadcheck numbers, and the status of
  completed items. Move finished work out of NOW/NEXT and flip the matching debt rows.
- Regenerate the version stamp: `fun src/prj/fun/gen-version.fun [YYYYMMDD] ["release"]`.
- Run `sh src/prj/fun/check-roadmap.sh` and fix any mismatch before tagging.
- Commit the changelogs, version stamp, and `ROADMAP.md` as `release: Fun X.Y.Z`.

## 2. Tag with a summary, never a bare tag

GitHub renders the annotated tag message as the release page body when the release has no description. A title-only (or lightweight) tag therefore leaves the published release page blank.

Every release tag is an **annotated** tag with this shape:

```text
Fun X.Y.Z

<one-line theme for the release>

Highlights since v<previous>:

- <2-6 prose bullets, one per user-visible change group>

Full list: CHANGELOG.md / CHANGELOG.zh.md.
```

Write the message to a file and tag from it, so the body keeps its blank lines and wrapping:

```bash
git tag -a -F /tmp/vX.Y.Z.txt vX.Y.Z
git push origin main
git push origin vX.Y.Z
```

- Tag the release commit, not a later one.
- Push the tag explicitly. `git push --tags` also pushes unrelated or stale tags.
- Check the result before publishing: `git tag -n99 -l vX.Y.Z`.
- For a point release, keep the note short but still name the bug and the observable fix.

## 3. Publish

- Create the GitHub release for the pushed tag.
- Leave the description empty (or paste the same summary) so the tag annotation is what readers see.
- Open the release page and confirm the notes render.

Pushing the tag also starts `.github/workflows/release.yml`. It verifies that
the tag matches `funRelease` in `src/core/version.inc`, finds the successful
regression run for that commit on `main`, downloads the build stages that run
uploaded, and attaches the archives, `SHA256SUMS`, `capabilities.json` and
`SBOM.cdx.json`. The tag annotation is used as the head of the release notes.
If the tag was pushed before the commit had a green main-branch run, the job
fails instead of publishing untested binaries.

## 4. Nightly prereleases (automatic)

`.github/workflows/release.yml` also runs every night at 04:37
Asia/Shanghai. It is a delivery channel, not a release event:

- A nightly is published only when code changed (`src/`, `fun/lib`,
  `fun/test`, `fun/demos`, `fun/demo`) since the previous nightly. Docs and
  CI-only changes do not produce one, and a day with no commits produces
  nothing at all.
- The date comes from the HEAD commit timestamp in Asia/Shanghai, not from
  the runner clock, so a delayed run does not produce tomorrow's date.
- The version is the next patch after the newest stable version, e.g.
  `v9.5.5-nightly.20261104`. In SemVer this sorts below `v9.5.5`. Nightly
  runs never modify `version.inc`, README, ROADMAP or CHANGELOG and never
  create a commit.
- The tag is created on the existing HEAD with `gh release create --target`.
  If a run is repeated for the same commit it reuses that tag; if a second
  commit lands the same day it uses `.2`, `.3`, and so on.
- Every nightly is a GitHub **prerelease**, so `releases/latest` keeps
  pointing at the stable release. Only the newest 14 nightlies are kept.

Manual runs: Actions -> **release** -> Run workflow. Choose `nightly` and tick
`force` to publish the current commit even when it has no new code changes.
This is also how to test the pipeline. Choose `stable` with a tag to re-upload
assets for an existing stable tag.

Each artifact carries `capabilities.json` describing regex, getapi/FFI,
runtime C compilation and the safe build. Missing optional dependencies are
reported there and in the release notes; they are never silently presented as
a full build.

Assets are protected by `SHA256SUMS` and accompanied by `SBOM.cdx.json`.
Sigstore/cosign signing is not enabled yet, so do not imply that signatures
exist.

Every Unix archive carries `install.sh`; the Windows archive carries
`install.cmd`, `install.ps1`, `uninstall.cmd` and `uninstall.ps1`. The package
job verifies their presence before publishing. `install.sh` is also uploaded
as a top-level release asset. See the README for the Windows PATH and file
association behavior.

### Monitoring

Scheduled workflows can be delayed for hours or dropped without a failure
event. Set the repository secret `HEARTBEAT_URL` to a monitor URL (for
example a healthchecks.io ping URL). A successful run, including a correctly
skipped night, pings it; a failed run pings `<url>/fail`. An external monitor
should alert after roughly one missed interval. Without that secret there is
no out-of-band signal that the schedule stopped running.

## Repairing a published tag

If a tag was published without a summary:

```bash
git update-ref refs/tags-backup/vX.Y.Z vX.Y.Z
git tag -f -a -F /tmp/vX.Y.Z.txt vX.Y.Z vX.Y.Z^{commit}
git push origin vX.Y.Z --force
```

- Keep the commit unchanged: force-update only the annotation.
- The local `refs/tags-backup/*` ref preserves the old tag object.
- Anyone who already fetched the old tag may see a "tag changed" notice on the next fetch. Code is not moved.
