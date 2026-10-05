# Changelog

## 0.2.0

* The Intercom panel asks for the account email when you sign in and
  remembers it. **Account email** is now optional; if set, it is the default
  until the first sign-in.
* The panel says plainly why a sign-in is needed ("No session yet", "The
  provider ended the session").
* Quiet logs before the first sign-in: one warning instead of a stream of
  restart tracebacks, and everything starts within a second of signing in.

## 0.1.0

* First release as a Home Assistant App.
* Ring events, door buttons (or locks), visitor photos, door-open history,
  Reject call, live video into go2rtc with Show camera and Next camera buttons.
* Sign-in from the Intercom panel (ingress): an emailed one-time link, no
  password stored.
* MQTT found through the Supervisor (Mosquitto app), or a broker and login of
  your own.
