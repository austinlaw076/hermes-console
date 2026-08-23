# Configure a Hermes server

Hermes Console connects directly to the server configured by the user. XPeta
Lab does not proxy conversations or operate a conversation backend.

## Before you start

- Install Hermes Agent and make its Gateway reachable from Android.
- Prefer HTTPS for remote access or a private network such as Tailscale/LAN.
- Do not expose Gateway, Dashboard, or Mobile Bridge directly to the public
  internet without TLS, authentication, and an appropriate network policy.
- Have the Gateway `API_SERVER_KEY` available. It is not a model-provider API
  key.

## Recommended pairing flow

1. In the app, choose **Connect server** and **Scan QR code**.
2. If you do not have a pairing QR yet, open **Prepare server** and run the
   command for the system that hosts Hermes.
3. Keep the QR code on the server screen and scan it, or paste the returned
   `hermes://pair` link.
4. Hermes Console checks Gateway, Dashboard, and Mobile Bridge before saving
   the connection.

The QR code or link may include an address and credentials. Treat it as a
secret: do not publish it, attach it to an issue, or use it in screenshots.

## Manual configuration

If pairing is unavailable, enter the relevant values manually:

- **Gateway URL**: the address reachable from the phone, preferably over HTTPS.
- **Gateway token**: the `API_SERVER_KEY` for this Hermes instance.
- **Dashboard/Admin URL**: optional; enables administrative features exposed by
  the server.
- **Dashboard authentication**: automatic, session token, or Basic Auth,
  according to the real server configuration.
- **Mobile Bridge**: optional; the app can discover its URL and store its token
  securely for features that require it.

Credentials are stored through Android Keystore. Do not reuse sample tokens or
paste OpenAI, OpenRouter, or other provider keys into the Gateway token field.

## Verify the connection

After saving the instance:

1. Open it and run the connection/capability check.
2. Confirm that Gateway responds and that the expected profile and model are
   shown.
3. If you use Dashboard or Mobile Bridge, verify each surface separately.
4. Enable read-only mode when the phone must not make remote changes.
5. Configure App Lock before storing additional credentials or using
   administrative actions.

## Common failures

- **Connection refused**: Gateway is stopped, listens only on loopback, or its
  port is blocked.
- **Timeout**: the phone has no route to the server; check Wi-Fi, VPN, or
  Tailscale.
- **Host not found**: check DNS or MagicDNS.
- **Invalid TLS**: use a trusted certificate or a private network; do not turn
  off device-wide security.
- **401/403**: the `API_SERVER_KEY` does not match, or Dashboard requires its
  own authentication.

For data destinations and optional services, read the
[privacy policy](PRIVACY_POLICY.md).
