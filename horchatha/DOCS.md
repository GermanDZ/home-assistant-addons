# HorchatHA

HorchatHA brings a cloud video intercom into Home Assistant. It signs in to
your own intercom account, gets rings the moment a visitor presses a panel,
shows the panel camera, keeps the visitor photos and opens your doors. Every
piece is a native Home Assistant entity, made through MQTT discovery.

It is not local control: the intercom's cloud is still in the loop, as it is
for the provider's phone app. HorchatHA runs next to Home Assistant and does
what that app does, as one more client of your account. It is not affiliated
with or endorsed by any intercom manufacturer or provider.

## What you get

One device per home (installation), with:

- **Ring** event per door, tagged with the door, when a visitor rings.
- **Open** button per door (or a lock, see `door_entity`).
- **Last visitor** photo per door; older photos stay in `/media/horchatha`.
- **Door opened** events from the account's open history: who opened which
  door, phones included.
- **Reject call** button: hang up a ringing call, as the phone app's decline.
- **Connectivity** sensor: on while rings can arrive and the sign-in works.
  Its attributes carry the details (last ring, token expiry, MQTT, go2rtc
  stream names).
- With live video on: a **Streaming** sensor, **Live video** and **Camera
  preview** switches, **Show camera** buttons per door and a **Next camera**
  button. Video goes into go2rtc; a WebRTC card plays it.

## Before you start

1. The **Mosquitto broker** app, installed and running. HorchatHA finds it by
   itself.
2. For live video, the **go2rtc** app.
3. Your provider's settings: the endpoints and app credentials (OAuth client,
   push project, app package and version) of the provider's mobile app. They
   are the same for every user of that app, but HorchatHA does not ship them;
   you enter them in the configuration.

## Install

1. Add this repository to the app store: **Settings → Apps → App store → ⋮ →
   Repositories**, `https://github.com/GermanDZ/home-assistant-addons`.
2. Install **HorchatHA**.
3. On the **Configuration** tab fill in the provider settings and your account
   email. Leave **Account password** empty.
4. Start it. The **Intercom** panel appears in the sidebar.

## Sign in

Open **Intercom** in the sidebar (admins only):

1. **Email me a link.** The provider emails a one-time sign-in link to the
   account, valid for about 10 minutes.
2. In the email, **copy the link without opening it**: opening it spends it.
   Paste it and press **Sign in**. If you already opened it, paste the address
   the browser ended on, or its code.

HorchatHA keeps the session alive by itself. If the provider ever ends it, the
Connectivity sensor turns off and the panel says why: sign in again there, no
restart needed. No password is stored unless you put one in the
configuration.

## Live video

1. Turn on **Live video** in the configuration and restart the app.
2. Read the stream names from the Connectivity sensor's `go2rtc_streams`
   attribute, e.g. `panel_0123abcd`.
3. Declare each one, **empty**, in `/config/go2rtc.yaml` and restart go2rtc:

   ```yaml
   streams:
     panel_0123abcd:
   ```

   go2rtc refuses a publish into a stream it doesn't know. Don't add a source
   or a transcode; HorchatHA publishes H.264 that go2rtc only relays.
4. The default **go2rtc RTSP URL**, `rtsp://172.30.32.1:8554`, is the go2rtc
   app on this host. If go2rtc's RTSP has a login, set the user and password.
5. Show it with a [WebRTC Camera](https://github.com/AlexxIT/WebRTC) card,
   e.g. while the Streaming sensor is on:

   ```yaml
   type: custom:webrtc-camera
   url: panel_0123abcd
   mode: webrtc,mse
   muted: true
   ```

Video only exists during a call (a ring, or **Show camera**). **Camera
preview** is off by default: when it's on, people at the door see the panel's
camera turn on.

## Configuration

Every option has a description in the Configuration tab. Some notes:

- **MQTT**: empty uses the Mosquitto app and its login for apps, which can
  read and write every topic. To restrict HorchatHA, give it a login of its
  own (`mqtt_user` / `mqtt_password`) and an ACL like:

  ```text
  user horchatha
  topic readwrite horchatha/#
  topic write homeassistant/device/horchatha/+/config
  topic read homeassistant/status
  ```

- **Door names**: the provider's door titles are often empty. `ZERO=Street,
  GENERAL=Garden` names the entities. A door's key is in its Ring events'
  `door` attribute.
- **Who opened**: `email=Name` pairs. Anyone not listed shows as `other`, so
  Home Assistant never stores email addresses.
- **Dry run**: log door opens, rejects and camera starts without doing them.

## Data and privacy

- The session token and push registration live in the app's data, which is
  part of Home Assistant backups. Encrypt your backups.
- Photos are kept under `/media/horchatha` for `archive_days` days.
- The door-open API on port 8080 is off unless you map the port. Its bearer
  token is generated on first start; set **Door API token** (32+ characters)
  if you need to call it.

## Only one at a time

Run one HorchatHA per intercom account. Two would share one push registration
and one MQTT client id, and keep knocking each other off.
