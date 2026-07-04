# Authorized use — read this first

SelkorinCam includes network-facing features (camera discovery, port probing,
passive traffic analysis). Those features are for **networks and devices you
own, or that you have explicit written authorization to test**. In most
jurisdictions, scanning, connecting to, or capturing traffic from cameras or
networks you do not own — or that your employer has not authorized you in
writing to test — is illegal, even "just to see if it's vulnerable."

## Rules this tool is built around

1. **Scope to your own subnet.** Discovery and port probing default to the
   local /24 that your Mac is already on. Do not point it at address ranges you
   were not asked to test.
2. **Passive analysis is read-only.** The traffic analyzer summarizes flow
   metadata (source/destination, port, protocol, packet counts). It does not
   decode payloads and does not attempt to extract credentials or media.
3. **No credential attacks.** The tool connects to a camera only with
   credentials **you** supply. It does not brute-force, spray default
   passwords, or exploit vulnerabilities to gain access.
4. **Keep authorization on file.** For a workplace engagement, keep the signed
   scope/authorization (which subnets, which hosts, which time window) before
   you run anything.

## What this tool deliberately does NOT do

These were left out on purpose because they only make sense for attacking
systems you don't control:

- WiFi deauthentication / disassociation or any denial-of-service.
- WPA/WPA2 handshake capture and offline cracking.
- Password brute-forcing or default-credential spraying against cameras.
- Exploiting camera firmware CVEs to gain unauthorized access.
- Any stealth / anti-detection / covert-recording behavior.

If a real authorized engagement needs deeper testing than inventory + config
audit + passive analysis, use established, auditable tooling (nmap, Wireshark,
ONVIF Device Manager, the vendor's own tools) under the signed scope — and log
what you do.

## Responsible "WiFi vulnerability testing" for your company cameras

The high-value, low-risk work is almost all configuration auditing:

- Inventory every camera (this tool helps) and confirm each one is expected.
- Check each camera is **not** reachable from the internet (no port-forwarding
  / UPnP exposure of 554/80/8000/37777, etc.).
- Confirm default credentials were changed and firmware is current.
- Confirm the camera VLAN is segmented from the rest of the corporate network.
- Confirm streams use TLS/SRTP where the device supports it.
- Passively review traffic (this tool helps) for plaintext credentials or
  unexpected external destinations.

That checklist finds the overwhelming majority of real camera/WiFi problems
without ever attacking anything.
