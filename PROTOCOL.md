# Screenshot Sync — Wire Protocol

LAN-only protocol between the Android app (client) and the Mac app (server). Version `1`.

## Transport

- TCP + TLS 1.2+, hand-rolled HTTP/1.1 subset (no external server framework on the Mac side).
- The Mac generates a self-signed TLS identity once per install, stored in Keychain. There is no CA — the client pins the certificate's SHA-256 fingerprint instead of trusting a certificate chain.
- Default port: `51828`. If unavailable, the Mac picks an ephemeral port and advertises the real port via Bonjour.

## Discovery

- The Mac advertises a Bonjour/mDNS service:
  - Type: `_screenshotsync._tcp`
  - Domain: `local.`
  - Instance name: the Mac's device name (e.g. `Sanoop's MacBook Pro`)
  - TXT record: `id=<device-uuid>` (stable per install, regenerated only if the user resets pairing), `v=1`
- After the initial QR pairing (below), the Android app never needs to be told the Mac's IP again — it resolves the current IP/port at send-time by browsing for `_screenshotsync._tcp` and matching TXT `id` against the `deviceId` it stored during pairing.

## Pairing (QR handshake)

1. User opens the Mac app's "Pair New Device" UI. Mac generates:
   - `pairToken`: random 256-bit value, base64url, valid for 3 minutes, single-use.
   - Displays a QR code encoding JSON:
     ```json
     {
       "v": 1,
       "deviceId": "<mac-device-uuid>",
       "deviceName": "Sanoop's MacBook Pro",
       "host": "192.168.1.23",
       "port": 51828,
       "certFingerprint": "<sha256-hex-of-DER-cert>",
       "pairToken": "<base64url>"
     }
     ```
   - `host`/`port` are a same-network-hint for the *first* connection only (before any mDNS browsing has happened); every connection after pairing re-resolves via mDNS.
2. Android scans the QR, connects via TLS to `host:port`, and refuses the connection unless the presented certificate's SHA-256 fingerprint matches `certFingerprint` exactly (certificate pinning — no system trust store involved).
3. Android sends:
   ```
   POST /pair HTTP/1.1
   Content-Type: application/json

   {"pairToken": "...", "androidDeviceName": "Sanoop's Pixel 8"}
   ```
4. Mac validates: token exists, unused, not expired. On success it:
   - Generates a long-lived `bearerToken` (random 256-bit value, base64url).
   - Persists a paired-device record `{androidDeviceId, androidDeviceName, bearerToken, pairedAt}` in Keychain/local store.
   - Responds:
     ```json
     {"status": "ok", "deviceId": "<mac-device-uuid>", "bearerToken": "...", "macDeviceName": "Sanoop's MacBook Pro"}
     ```
   - Marks the `pairToken` as used (rejects replay).
5. Android stores `{macDeviceId, macDeviceName, bearerToken, certFingerprint}` in EncryptedSharedPreferences. This is everything it needs for all future uploads.

Failure responses: `400` malformed body, `401` invalid/expired/reused token.

## Upload

Sent for every newly detected screenshot, once the device is paired.

```
POST /upload HTTP/1.1
Authorization: Bearer <bearerToken>
X-Device-Id: <android-device-id>
X-Filename: Screenshot_20260717_143210.png
X-Checksum-Sha256: <hex>
Content-Type: image/png
Content-Length: <n>

<raw image bytes>
```

Mac behavior on receipt:
1. Validate `Authorization` bearer token against a paired device. `401` if unknown/revoked.
2. Compute SHA-256 of the body, compare to `X-Checksum-Sha256`. `400` on mismatch.
3. Dedupe: if this checksum was already accepted in the last 5 minutes, respond `200 {"status": "duplicate"}` without re-saving or re-pasting (protects against client retries double-delivering).
4. Write the file to the configured destination folder (default `~/Pictures/ScreenshotSync/`) as `<AndroidDeviceName>_<yyyyMMdd_HHmmss>.png` (collision-suffixed if needed).
5. If "auto-paste to Figma" is enabled AND `NSWorkspace.shared.frontmostApplication.bundleIdentifier == "com.figma.Desktop"`: copy the image to the general pasteboard and synthesize ⌘V via `CGEvent`.
6. Respond `200 {"status": "ok", "pastedToFigma": true|false}`.

Response codes: `200` success/duplicate, `400` bad request/checksum mismatch, `401` unauthorized, `413` payload too large (cap: 25 MB), `500` server error (e.g. disk write failure).

## Retry semantics (Android side)

- Uploads that fail (network error, Mac unreachable, non-2xx) are queued locally (Room DB: filename, bytes/uri, checksum, attempt count, next-retry-at).
- Backoff: 5s, 15s, 60s, 5min, then every 15min, capped at 24h of retries before giving up (with a user-visible notification).
- Successful `200` (including `duplicate`) removes the item from the queue.

## Security notes

- No CA trust — pinning is mandatory. Any TLS handshake presenting a fingerprint that doesn't match the stored one must be rejected before any HTTP is exchanged.
- `pairToken` is single-use and short-lived specifically so that someone glimpsing the QR code after the pairing window closes can't join.
- `bearerToken` is long-lived; the Mac app's UI must offer a way to view/revoke paired devices (removes their record, future requests get `401`).
- The server only binds to LAN interfaces, never `0.0.0.0` on a public-facing sense beyond the local network — this is inherent to using local Bonjour + private IP ranges, but the Mac app should still avoid disabling the OS firewall prompt.
