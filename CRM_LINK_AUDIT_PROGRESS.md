# Carta CRM Link Audit and Progress Report

**Report date:** 2026-09-24  
**Scanned target:** `C:\Users\SAWAI\.codex\.tmp\plugins\plugins\carta-crm`  
**Overall status:** Manifest links pass; runtime implementation is not present in this bundle.

## Executive Summary

The discovered Carta CRM package is a small Codex app/plugin bundle containing three files:

- `.app.json`
- `.codex-plugin/plugin.json`
- `assets/app-icon.png`

Both JSON files parse successfully. Every local path referenced by `plugin.json` resolves to an existing file. The public website, privacy policy, terms of service, and repository URLs were reachable when checked on 2026-09-24. No broken or missing links were found in the available package.

This package does not contain the CRM application's source code, routes, UI pages, API implementation, tests, or documentation. Those areas therefore remain outside the verified scope of this audit.

## Link and Reference Audit

| Reference | Target | Result |
|---|---|---|
| Apps manifest | `./.app.json` | Pass — file exists and JSON is valid |
| Composer icon | `./assets/app-icon.png` | Pass — file exists |
| Logo | `./assets/app-icon.png` | Pass — file exists |
| App identifier | `asdk_app_69d6804c5c2481919b2674401922ebba` | Pass — value is present |
| Author URL | `https://carta.com` | Pass — reachable |
| Website/homepage | `https://carta.com` | Pass — reachable |
| Privacy policy | `https://carta.com/legal/privacy/privacy-policy/` | Pass — reachable |
| Terms of service | `https://carta.com/legal/terms-agreements/terms-service/` | Pass — reachable |
| Repository | `https://github.com/openai/plugins` | Pass — reachable |

## Missing or Incomplete Project Elements

These are not broken links, but they limit project completeness and verification:

1. **No CRM source code in the bundle.** The package links to a hosted app ID instead of including implementation code.
2. **No README or setup documentation.** There are no local instructions for authentication, permissions, configuration, or troubleshooting.
3. **No automated tests.** Manifest validation and app connectivity are not covered by a local test suite.
4. **No screenshots.** The manifest declares an empty `screenshots` array.
5. **No declared interface capabilities.** The manifest declares an empty `capabilities` array. This may be intentional for a connector-only app, but it should be confirmed against the publishing requirements.
6. **Generic repository link.** The repository points to the top-level `openai/plugins` repository rather than an app-specific source path.
7. **Truncated short text.** The package description and `shortDescription` end with `...`, which makes the listing copy look incomplete.

## Progress

- [x] Located the Carta CRM package
- [x] Inventoried all package files
- [x] Parsed both JSON manifests
- [x] Checked every local manifest path
- [x] Checked every public URL in the manifest
- [x] Recorded missing project elements and limitations
- [ ] Validate hosted CRM authentication and permissions in a connected session
- [ ] Run end-to-end CRM actions against the hosted app
- [ ] Add documentation and automated manifest checks, if this package is maintained locally

## Current Assessment

**Link integrity:** Complete — no broken references found.  
**Package completeness:** Partial — valid as a thin hosted-app descriptor, incomplete as a standalone software project.  
**Runtime confidence:** Not established — the hosted app was not authenticated or exercised during this file-level audit.

## Recommended Next Steps

1. Confirm that the empty `capabilities` and `screenshots` fields are intentional.
2. Replace truncated description text with a complete concise description.
3. Point `repository` to an app-specific source directory or documentation page when available.
4. Add a README covering connection setup, required access, data scope, and support contacts.
5. Test the hosted app ID in a connected Carta CRM session and document the results here.
