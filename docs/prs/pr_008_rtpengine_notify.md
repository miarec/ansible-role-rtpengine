# 2026-11-15-rtpengine-notify

Fixes a medium-severity bug that can leave a host without RTPEngine for 5 seconds after any start or restart of the service.

## 🎯 Problem

A start or restart of `rtpengine.service` sometimes stops the new RTPEngine a few milliseconds after it logs "Startup complete". systemd starts it again 5 seconds later. Until then, the host has no RTPEngine, so Kamailio's offers to it fail or go to another RTPEngine of the cluster. The SBC end-to-end tests hit this 3 times in about 20 minutes on a loaded machine.

---

## 👀 What changes for users

- Starts and restarts of RTPEngine no longer end in an unexpected stop and a 5-second gap.
- `systemctl start` and `systemctl restart` return only when RTPEngine accepts commands, not as soon as the process starts. The 10-second start timeout now covers that wait.
- RTPEngine's warnings and errors appear twice in the journal. `rtpengine.log` doesn't change.

---

## 🐛 Bug details

* **Severity**: medium. The outage lasts 5 seconds and the service recovers by itself, but any start can hit it, and the likelihood grows with CPU load.
* **Symptom**: "Startup complete", then "shutting down" a few milliseconds later, "Deactivated successfully", and "Scheduled restart job, restart counter is at 1".
* **Exposure**: every version of the role since its first commit (`36dca86`, 2024-09-03). There's no workaround.

RTPEngine ran itself in the background. When the process that systemd started exited before its child wrote the PID file, systemd found no running service, ran the stop command, and the stop command then found the child's PID file and stopped the new RTPEngine.

---

## 💥 Impact

* **Who is affected**: every host that the role configures, on every start: deployment, restart after a configuration change, reboot, and automatic restart.
* **Who is not affected**: no one is exempt. Lightly loaded hosts hit the bug rarely.
* **Conditions**: the child loses a race of a few system calls against systemd. CPU contention makes that likelier.

---

## 🔧 Implementation notes

- `Type=notify` with `--foreground` follows Sipwise's own unit. `Type=forking` would also have closed the race, but it keeps the PID file and fails a slow start at the timeout.
- **Breaking:** the role removes `rtpengine_pid_dir` and `rtpengine_pid_file`. Inventories that set them keep working, and the variables have no effect.
- Upgraded hosts keep an empty `/run/rtpengine` folder until their next reboot.

---

## 📌 Related issues

Closes #6
