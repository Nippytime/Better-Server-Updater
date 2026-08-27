# BSU - Better Server Updater

BSU is a server-side restart coordinator for Project Zomboid Build 42.

It checks loaded Workshop items, logs update details, warns players, disconnects clients before saving, waits for the save to finish, and quits the server process so an external supervisor can restart it.

## Core flow

1. Server loads shared BSU modules.
2. Server loads BSU server modules and records the startup timestamp.
3. After `StartupCheckDelaySeconds`, automatic Workshop polling begins if `EnableWorkshopPolling` is enabled.
4. BSU calls `getSteamWorkshopItemIDs()` and `querySteamWorkshopItemDetails(...)`.
5. Each returned Workshop item is compared against the server startup timestamp using `getTimeUpdated()`.
6. Updated Workshop titles and IDs are logged.
7. If `RestartOnWorkshopUpdate` is enabled, BSU schedules a restart.
8. If `WaitForServerEmpty` is enabled, or `RestartDelayMinutes` is `0`, the restart waits until the server is empty.
9. Otherwise, players receive countdown warnings based on `WarningScheduleSeconds`.
10. When the restart begins, BSU asks clients to disconnect if `DisconnectPlayersBeforeSave` is enabled.
11. BSU keeps resending disconnect requests every `DisconnectRetrySeconds` until the server is empty or `DisconnectGraceSeconds` expires.
12. If `SaveBeforeQuit` is enabled, BSU calls `saveGame()`.
13. BSU waits for `OnPostSave` or `OnServerFinishSaving`. If neither arrives, it continues after `SaveTimeoutSeconds`.
14. BSU waits `QuitDelaySeconds`.
15. If `QuitServer` is enabled, BSU calls `getCore():quit()`.

## Automatic restart scheduling

BSU can also trigger the same restart lifecycle without waiting for a Workshop update or admin command. `ScheduledRestartMode` has three sandbox choices:

- `Disabled` - no automatic clock/interval restart.
- `Daily at server-local time` - restart every day using `DailyRestartHour` and `DailyRestartMinute`. The time is based on the dedicated server host/JVM local timezone.
- `Every X hours from server startup` - restart after `RestartIntervalHours` real-world hours from the current server session start. A real process restart creates a new session anchor.

`ScheduledRestartLeadMinutes` controls how early the automatic target enters BSU's normal restart countdown. `WarningScheduleSeconds` continues to define the actual warning points, but only warning points inside the lead window can occur.

The scheduler stays separate from the active restart state until that lead window begins, so a restart many hours away does not block Workshop-triggered or manual restarts.

### Live sandbox changes

The vanilla server sandbox UI synchronizes applied values to the server and rebuilds `SandboxVars`. BSU reads current settings on its throttled one-second server cadence, so schedule changes normally take effect within about one second without reloading the mod or restarting the server.

- Before disconnect/save begins, changing or disabling the automatic cadence safely recalculates/cancels the pending automatic restart.
- Changing only the warning lead shortens/extends the active lead when it is still safe to do so.
- If `WaitForServerEmpty` is disabled while an automatic restart is waiting for an empty server, BSU continues the restart immediately.
- Once disconnect/save/quit has begun, BSU does not try to reverse the shutdown; the changed schedule applies to the next server session/cycle.
- If an interval is shortened so that the server is already overdue, BSU starts a fresh `ScheduledRestartLeadMinutes` warning window rather than quitting players without warning.
- Cancelling an automatic restart with `/cancelrestart` skips that occurrence instead of re-arming it on the next tick.

## Notification delivery

BSU has one server-side notification pipeline. Sandbox settings choose how each client presents those messages:

- `NotifyChat` - normal in-game chat. Enabled by default, preserving the original BSU behavior.
- `NotifyHalo` - vanilla halo text above local players. Alerts use the bad-highlight color; informational messages use the good-highlight color.
- `NotifyCenterAlert` - vanilla center-screen server alert for critical alerts only.
- `NotifyAlertSound` - vanilla UI sound for critical alerts only.

The methods can be combined. `BroadcastWarnings` still decides whether restart countdown warnings are emitted at all; the four notification options decide how emitted messages are presented.

`WarningScheduleSeconds` is now actually exposed in `sandbox-options.txt`. It accepts comma- or semicolon-separated seconds. The shipped default uses semicolons because the sandbox definition parser itself uses commas to delimit fields.

Joining clients receive one current restart-state snapshot through ModData. Ongoing state changes use the normal BSU server-command path, which avoids duplicating live restart alerts while still informing players who join during an already-pending restart.

## Commands

Admin commands are enabled by default:

- `/restart`
- `/restartnow`
- `/schedulerestart N`
- `/cancelrestart`
- `/checkworkshop`

`AdminOnlyCommands` controls whether BSU requires admin/mod-management permission. `ManualCommandsEnabled` can disable the command bridge entirely.

## Restarting the process

BSU can safely quit the server from Lua. Relaunching the same dedicated server process from inside the already-terminating process is not a reliable supported path.

Use one of these to restart after BSU quits:

- systemd service with `Restart=always`
- Docker restart policy
- AMP/Pterodactyl/other server panel restart behavior
- Windows service wrapper
- batch/shell loop
- one of the wrapper scripts included with the mod (below)

## Included restart wrappers

BSU ships with a simple restart loop for both Windows and Linux. Each one launches the dedicated server, waits for the process to exit, and starts it again. That covers Workshop-triggered restarts, scheduled restarts, and admin-triggered restarts alike.

Both files live in the mod folder:

```
BetterServerUpdater\Contents\mods\BetterServerUpdater
```

| File as shipped | Rename to | Platform |
| --- | --- | --- |
| `StartServer64_BSU_Windows.bat.txt` | `StartServer64_BSU_Windows.bat` | Windows |
| `start-server_BSU_Linux.sh.txt` | `start-server_BSU_Linux.sh` | Linux |

The Steam Workshop uploader rejects raw `.bat` and `.sh` files, so both scripts ship with a trailing `.txt`. **They will not run until that extension is removed.**

### Windows

1. Rename `StartServer64_BSU_Windows.bat.txt` to `StartServer64_BSU_Windows.bat`.
2. Copy it into the dedicated server folder, normally `Steam\steamapps\common\Project Zomboid Dedicated Server`.
3. Launch the server with that `.bat` instead of the stock start script.

If the `.txt` is not visible, enable **File name extensions** under the View tab in File Explorer. Extensions are hidden by default, which is the usual cause of a file still named `.bat.txt`.

### Linux

1. Rename `start-server_BSU_Linux.sh.txt` to `start-server_BSU_Linux.sh`.
2. Copy it into the dedicated server folder.
3. Mark it executable and run it instead of the stock start script.

```
chmod +x start-server_BSU_Linux.sh
./start-server_BSU_Linux.sh
```

### Downloading without renaming

Both scripts are also in the repo with the correct extension already applied:

- [StartServer64_BSU_Windows.bat](https://github.com/Nippytime/Better-Server-Updater/raw/main/StartServer64_BSU_Windows.bat)
- [start-server_BSU_Linux.sh](https://github.com/Nippytime/Better-Server-Updater/raw/main/start-server_BSU_Linux.sh)

GitHub serves `.sh` as plain text, so that link may open in the browser rather than downloading. Use right click > Save link as, `curl -O`/`wget` with the raw URL, or take the whole repo as a [zip](https://github.com/Nippytime/Better-Server-Updater/archive/refs/heads/main.zip).

Either script is only a supervisor. Editing JVM arguments, memory limits, or server name still happens the same way it does in the stock start script.

## Safety notes

BSU does not call unverified direct `GameServer.kick(...)` Lua code. It uses confirmed Lua-visible command traffic to ask clients to disconnect, then saves and quits from the server side.

`QuitServer=false` is useful for dry-run testing. It runs the whole lifecycle without actually quitting the server.
