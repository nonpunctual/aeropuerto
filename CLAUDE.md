# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project facts

Project and codebase facts (naming, packaging conventions, release process) belong in project documentation: this file and `README.md`, not in Claude's cross-session memory system. If something learned about this project seems worth persisting, tell the user you are doing it so they can edit as needed and write it into the project documentation files instead of saving it as a memory.

## Signing and TCC/Location testing

Never test unsigned or ad-hoc-signed builds against privacy-gated frameworks (Location Services/CoreLocation, or any other TCC-style consent). Never delete an app bundle or build directory that still has a live, unresolved Location Services/TCC reference.

A properly signed app with a real Team ID and one stable, consistently `lsregister`ed identifier gets cleanly pruned by macOS from locationd's `clients.plist` once it's actually gone. Unsigned/ad-hoc-signed test builds and haphazard deletes don't resolve the same way, their references go orphaned instead. Brock had to manually clear 5 such orphaned entries in `/private/var/db/locationd/clients.plist`, which additionally required temporarily disabling SIP since normal (even root) writes to that file are blocked, traced to past ad-hoc test builds across two projects (`aeropuerto`, and a separate `TSP`-scoped `WifiScanTest`/`wifi-scanner` prototype) using inconsistent one-off identifiers.

Only exercise Location/Camera/Microphone/etc. permission flows against a properly signed build with a real Team ID and one stable identifier, registered via `lsregister` on every build (`build.sh` already does this correctly, don't add anything on top of it to force re-prompting). Disabling SIP to hand-edit `clients.plist` is a one-off manual cleanup, not something to script or repeat routinely.

## Working with Claude on this project

Wait for explicit direction before responding or acting further. If told "I will let you know when to respond," take that literally: stay silent, no tool calls, no reply, on subsequent inputs (including corrections or new information) until given an explicit cue to respond again.

## Release process

Any change to `Sources/aeropuerto/` that's visible or behaviorally different to the user (not a pure internal refactor) ships as a version bump. Don't leave a functional change committed to main unversioned.

Standard workflow, every time:

1. Commit the functional change with a concise message.
2. Bump the version in `Sources/aeropuerto/Info.plist` (source of truth for `CFBundleVersion`/`CFBundleShortVersionString`) and `distribution.xml`'s `pkg-ref version`.
3. `swift build` - confirms it compiles.
4. `./build.sh` - rebuilds the signed `.app` bundle and syncs `payload/`.
5. `/Users/Shared/scripty-legacy/build.pkg.sh --distribution distribution.xml payload Resources Scripts aeropuerto-<version> com.nonpunctual.aeropuerto <version> "" "" com.nonpunctual.aeropuerto "" component-plist.plist` - builds, signs, and notarizes `aeropuerto-<version>.pkg` (see the script's own header comments if the positional-arg order ever needs rechecking).
6. Commit the version bump as `Bump to <version>`.
7. `git tag v<version>` on that commit.
8. Push the commit(s) and the tag.
9. `gh release create v<version> aeropuerto-<version>.pkg --title "aeropuerto <version>" --notes "..."`.
10. Delete the previous version's release and tag (`gh release delete vPREV --yes --cleanup-tag`).

The `.pkg` is never committed to git (`*.pkg`, `aeropuerto.app/`, and `payload/` are all gitignored). It only ever exists as a GitHub release asset and a transient local build artifact. Delete the local `.pkg` once it's uploaded. Only the newest version's release/tag/`.pkg` should exist, on GitHub and locally - git history is the record, not the releases list.
