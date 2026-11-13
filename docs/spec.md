# ClaudeGauge specification

Behavior shared by every ClaudeGauge implementation (macOS today, Windows later).
The macOS code in `Sources/ClaudeGaugeCore` is the reference; this document records the rules so a
port does not have to read Swift. Where the two disagree, fix the code or this file, not just one.

## 1. Data source

ClaudeGauge shows the usage limits of a Claude subscription (the 5-hour session and the weekly limit).

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <Claude Code OAuth access token>
anthropic-beta: oauth-2025-04-20
```

- **Unofficial and undocumented.** This is the endpoint Claude Code itself uses. It can change or
  disappear without notice, and Anthropic's terms may restrict using Claude Code's token from another
  app. Check the current terms before distributing a build.
- Timeout 10 s. No redirects are followed. No cookies, no cache (`reloadIgnoringLocalCacheData`).
- Decoding is lenient: unknown keys are ignored, and a field with an unexpected shape becomes
  "absent" instead of failing the whole response.

### 1.1 Response fields used

| Field | Meaning |
| --- | --- |
| `five_hour.utilization` | Percent used (0–100, may exceed 100) of the 5-hour session. |
| `five_hour.resets_at` | ISO 8601 reset time. `null` when the window has not started. |
| `seven_day.utilization` / `.resets_at` | Same, for the weekly limit. |
| `limits[]` with `kind == "weekly_scoped"` | Per-model weekly limit. `scope.model.display_name`, `percent`, `resets_at`. |
| `seven_day_breakdown.rows[]` | Weekly consumption by surface: `key`, `display_name`, `percent`. |

Everything else (`extra_usage`, `pace`, `weekly_scoped_shares`, …) is ignored for now.

- `resets_at` carries fractional seconds and a `+00:00` offset, e.g. `2026-11-11T10:59:59.901678+00:00`.
  Parse with and without fractional seconds. The API reports a boundary at `:59:59.9`, so **round the
  displayed reset time to the nearest minute** (`10:59:59.9` → `11:00`).
- `seven_day_breakdown.rows[].percent` is a **share of total consumption** (sums to 100), not a
  percent of a limit.
- A `200` whose body has neither `five_hour.utilization` nor `seven_day.utilization` is treated as an
  invalid response (not as "0%"), so the previous good value is never overwritten with an empty one.

### 1.2 Status codes

| Status | Result |
| --- | --- |
| 200 | Success (subject to the check above). |
| 401, 403 | `unauthorized` → show the refresh notice (§3). |
| 429 | `rateLimited` → back off (§5). |
| 5xx | `server`. |
| other / transport error | `unexpectedStatus` / `network`. |

Errors carry only the case and the status code. Never include the body or the token.

## 2. Credentials

Claude Code stores its OAuth credentials; ClaudeGauge only reads them.

- macOS: Keychain generic password, service `Claude Code-credentials`, account = the current user name,
  read with `/usr/bin/security find-generic-password -a <user> -s "Claude Code-credentials" -w`
  (15 s timeout; on timeout SIGTERM, then SIGKILL after 2 s). Pass the child only `PATH`, `HOME` and
  `USER` in its environment, and stop it if its output exceeds 1 MiB. The command result (stdout) must
  not be printable: redact it in descriptions and reflection.
- The output is JSON, or the same JSON as a hex string (when it contains non-printable bytes).
- Use **only** `claudeAiOauth.accessToken` and `claudeAiOauth.expiresAt`.
  `expiresAt` ≥ 1e11 is milliseconds, otherwise seconds.
- The same item also holds credentials of other MCP servers (`mcpOAuth`). They must never be decoded
  into a model type, kept, logged, or persisted.
- **Never use the refresh token and never refresh.** Refreshing from a second app can invalidate the
  token Claude Code holds. When the token is (nearly) expired the app does not call the API and asks
  the user to open Claude Code instead (§3).
- Read the credentials on every fetch; do not keep the token in memory or on disk between fetches.

## 3. Token expiry

`expired = expiresAt < now + 5 minutes`. The margin covers a token that would expire mid-request.

When expired (or on 401/403) the popover shows **"Open Claude Code once to refresh"**.
No other failure has special text; the last good values and `Last updated HH:mm` stay visible.

## 4. Forecast

Linear extrapolation of the current pace over a window of known length.

- Window lengths: 5 h session = 5 × 3600 s, weekly = 7 × 24 × 3600 s.
- `windowStart = resetsAt − length`, `elapsed = clamp(now − windowStart, 0, length)`,
  `ratio = elapsed / length`.
- If `resetsAt` is absent (window not started) there is no forecast → `Forecast: —`.

| Condition | Result |
| --- | --- |
| `utilization ≥ 100` | reached (a fact, not a forecast) |
| `ratio < 0.03` | `Forecast: measuring` (too early to be meaningful) |
| `0.03 ≤ ratio < 0.1` | **rough** forecast: `Forecast: ~141%` |
| `ratio ≥ 0.1` | `Forecast: 141%` |

For the last two rows, `projected = utilization × length / elapsed`.
The thresholds are `minimumElapsedRatio = 0.03` and `reliableElapsedRatio = 0.1`
(weekly: about 5 h and 16.8 h after the reset; 5h session: 9 min and 30 min).

- `projected` is shown as is, **not capped at 100%** (`Forecast: 120%`).
- If `projected > 100`, the time the pace reaches 100% is
  `now + (100 − utilization) × elapsed / utilization`, shown as `(100% at HH:mm)` next to the forecast.
  It is shown only when 100% is reached before the reset, and **not while the forecast is rough**
  (an early, unreliable number should not raise an alarm).
- The window is a warning (`isWarning`) when 100% is reached, or will be (with a reliable forecast),
  before the reset.
- A rough forecast has the same color as any other; only the `~` marks it.

## 5. Refresh schedule

Data changes only on a manual **Reload** or on the scheduled auto-refresh. Launching the app, waking
from sleep, or opening the popover does not fetch by itself; a fetch happens only when the scheduled
time (below) has come, including right after a sleep that outlasted it.

- Auto-refresh interval: 1, 3, 5 or 10 minutes (default 3). Stored values are clamped to 60–600 s.
- Next fetch = `lastAttemptAt + interval`. `lastAttemptAt` is the time of the last attempt, successful
  or not, and survives restarts. If it is already past on launch, fetch immediately; otherwise wait for
  the remainder. If the clock moved backwards (attempt in the future), wait at most one interval.
- Reload is refused when the last attempt was less than **60 s** ago (also across restarts).
- Backoff: the interval is `base × 2^n`, capped at 30 min, where `n` = consecutive `429`s +
  consecutive failures to read the credentials (Keychain locked, access denied, timeout). Each of the
  two counts is capped at 10, so a tampered stored value cannot overflow. Any success resets both.
  A failure that proves the credentials were read (expired token, API error) resets the credentials
  count. The 429 count survives restarts; the credentials count does not.
- Backoff applies only to the schedule. A manual Reload ignores it (only the 60 s cooldown applies), so
  a user who has just granted Keychain access can retry immediately. A success resets the backoff.
- Changing the interval recomputes the remaining wait from `lastAttemptAt`.
- Record `lastAttemptAt` when an attempt **starts**, not when it ends. Otherwise a schedule recomputed
  during a slow attempt sees a stale time, computes a wait of zero, and loops without sleeping.
- Only one fetch runs at a time.

## 6. Reset handling

A window whose `resetsAt ≤ now` is **expired**: its stored utilization is stale, so show it as `—`.
5h and weekly are judged independently. When the weekly window is expired, its breakdown and scoped
limits are hidden too. A window with no `resetsAt` is never expired. `Last updated` still shows the
last successful fetch time. The UI switches to `—` at the reset moment (schedule a tick at the earliest
upcoming `resetsAt`), without waiting for the next fetch.

## 7. Display rules

All text is English.

- **Percent**: rounded to the nearest integer (`42.5` → `43%`). Non-finite or absurd values → `—`.
- **Level colors**: green `< 70`, yellow `70 ≤ p < 90`, red `≥ 90`.
- **Remaining time**: at most two units: `3h30m`, `6d3h`, `2h`, `45m`, `<1m`.
- **Clock**: `HH:mm` (24 h). If the date differs from today: `M/D HH:mm` (`11/12 06:59`).
- **Reset line**: `Resets at 21:40 (3h30m remain)`.
- **Last updated**: `Last updated 19:35`.

### 7.1 Menu bar

- Default: a nested donut (outer ring = 5h, inner ring = weekly), then two lines of text
  (top = 5h percent, bottom = weekly percent).
- Alternative style "Bars": two horizontal bars instead of the donut.
- The percent text can be turned off. Its color is fixed white (the menu bar background depends on the
  wallpaper, not on the system appearance).
- An expired or missing window shows `—`.

### 7.2 Popover

One row per window (5h session, Weekly):

```
5h session        60%   Forecast: 120% (100% at 21:40)
[=========================------------]
Resets at 21:40 (3h30m remain)
```

plus `Last updated HH:mm`, the refresh notice when needed, a Reload button, a settings toggle, and Quit.
Settings (inline in the popover): menu bar style, show percentages, refresh interval, launch at login.

## 8. Persistence

The only thing stored is non-secret state, so the app can start without a fetch:

- last snapshot (percentages, reset times, breakdown, fetch time), `lastAttemptAt`, consecutive 429
  count, and the user's settings.
- Never store a token, an expiry, or any Keychain content. The failure kind is not stored either.
- A corrupted stored value is ignored (treated as "nothing stored").

macOS: `UserDefaults`, key `lastUsage` (JSON).

## 9. Not in the MVP

- Weekly breakdown (Claude Code / Chats / Cowork). Parsed already; no UI.
- Per-model weekly limits (e.g. a model-specific cap). Parsed already; no UI.
- Windows implementation: only §2 (where Claude Code keeps its credentials) and the UI layer need
  platform-specific work; the rest of this document is meant to apply unchanged. Verify the Windows
  credential location before starting.
