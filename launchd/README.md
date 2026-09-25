# launchd

Every scheduled job is one plist. The plist is the only source of truth for cadence; the docs that used to list schedules drifted within weeks and were retired.

Two lessons, each of which cost days:

1. **Calendar jobs do not fire without a GUI login.** On a machine that sits at the login window, `StartCalendarInterval` jobs never run; `StartInterval` jobs do. `reliability/calendar-dispatcher.py` runs on an interval and replays calendar jobs whose window has passed.
2. **`LimitLoadToSessionType = Background` or the job cannot be bootstrapped over SSH.** Without it, `launchctl bootstrap user/<uid> <plist>` fails with `Bootstrap failed: 5: Input/output error` when there is no GUI session. Every plist here declares it.

The three examples: an interval job (the dispatcher), a calendar job on the always-on machine (the morning brief), and a calendar job on the laptop (weekly calibration).
