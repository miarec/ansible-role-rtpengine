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

## 🧪 How the fix was proved

All runs used one container from `ghcr.io/miarec/rtpengine:26.0.1.28-ubuntu2604` (systemd 259.9), with systemd's debug log on. The same container ran the unit from `master` first, and then the fixed unit.

**Forced race.** The method comes from #6. `strace` attaches to the process that systemd starts and delays the child's `setpgid()` by 20 ms, which makes the child lose the race on every start. A 3% CPU quota on the unit gives `strace` time to attach.

| Two starts each | `master` | This PR |
| --- | --- | --- |
| systemd's log | "Can't open PID file … after running", "Changed running -> stop", `ExecStop` runs | "Got notification message: READY=1" |
| RTPEngine | "Startup complete", then "shutting down", then a restart 5 s later | Keeps running, and `MainPID` is RTPEngine itself |
| `strace` | A fork with `SIGCHLD`, the parent's `exit_group(0)`, and the delayed `setpgid()` | No fork, so there's no race to delay |

**Without the forced delay.** 100 `systemctl restart` runs, 1 s apart, under a 3% CPU quota:

| | `master` | This PR |
| --- | --- | --- |
| Times systemd found the PID file missing or empty | 20 | 0 (no PID file) |
| Stops where `pkill` failed | 67 | 0 |
| Stops that ended in SIGKILL after the 10 s timeout | 52 | 0 |
| Clean starts (`READY=1`) and clean stops (SIGTERM) | No | 100 of 100 |

Under a 5% quota, the `master` unit also lost one start in 40 restarts, with the same log lines as in #6.

**Regression test.** A new testinfra test checks that the unit is `Type=notify`, has no PID file, and has `NRestarts=0`, and that systemd's `MainPID` is the `rtpengine --foreground` process.

---

## 📌 Related issues

Closes #6
