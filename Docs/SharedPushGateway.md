# Shared push gateway readiness

Food reserves the shared gateway application ID `food` for bundle
`org.thescudders.food`. The checked-in `PUSH_GATEWAY_URL` is deliberately
empty, so the gateway transport cannot be selected at runtime.

This change supplies only the provider-neutral HTTP contract, configuration
parser, and Security-backed installation identifier. Food does not yet have an
application account or a user-facing notification feature, so it does not
instantiate a notification manager, request notification permission, register
an APNs token with this transport, or submit an event.

The existing `remote-notification` background mode and APNs entitlement are
CloudKit infrastructure for `NSPersistentCloudKitContainer`. They are not
gateway activation and must not be intercepted or altered by this module.

## Activation gates

Runtime activation is blocked until one product change defines all of the
following together:

- a real user-facing notification and its consent copy;
- an account/identity model that can supply the gateway bearer token;
- a canonical source event and recipient rules;
- notification tap and foreground behavior;
- staging and production gateway configuration; and
- the complete physical-device matrix, including denied permission, token
  rotation, account switching, TestFlight production APNs, and iCloud-sign-out
  regression coverage where applicable.

The gateway itself is independent of iCloud identity. Food's current household
sharing is not: it continues to require CloudKit and the user's iCloud account.

## Deployment and rollback

There is nothing to deploy for this readiness change. Keep
`PUSH_GATEWAY_URL` empty in both build configurations. A future activation PR
must inject the environment URL through build configuration, while the stable
application ID remains `food`; no credential or APNs private key belongs in
the app.

Rollback is removal of the unused readiness module and its settings. Because
no lifecycle code calls it, rollback does not affect CloudKit sync, household
sharing, APNs registration, or user-visible behavior.
