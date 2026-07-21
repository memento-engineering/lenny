## Summary

UiAutomator2Backend drives native Android apps over Appium — the concrete sibling of AppiumBackend (iOS), keeping all Android divergences (hierarchy XML parse, content-desc a11y id, attribute/password masking, back press) inside the impl per the seam contract. The CLI's --platform flag (via backendForPlatform) now routes platforms to the right backend; unknown platforms throw loudly instead of silently defaulting to iOS. A complete Android Auth0 round-trip e2e proves dual-host end-to-end parity on Android, closing the lenny-qxx epic's Android gap.

## Circuit receipt

- rebase: clean
- revalidate: passed
- description: inference
- commits: 10 (9 conventional, 7 trailered)
  - off-policy: `feat(binding): extensionsReady — the embedder's post-registration readiness barrier` — the subject is 83 chars (max 72)

## Committee

- review: grades=code-validation=A,spec-adherence=A,regression-risk=B,test-coverage=B spread=1 rule=all-approve

## Validation

- plan: `cd packages/leonard_native && dart analyze && dart test && cd ../leonard_cli && dart test test/dogfood_auth0_android_e2e_test.dart`

Refs: lenny-qxx.7