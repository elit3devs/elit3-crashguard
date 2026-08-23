# Elit3 Crash Guard

Protection layer that blocks crash methods

Every action also prints to the server console and can optionally be mirrored to a
Discord webhook.

## Requirements

- **OneSync** enabled (`set onesync on` / `infinity` in your server.cfg) - the entity
  events and mirrored ped natives this resource relies on only exist under OneSync.
  
- Recommended: update **ox_lib** to v3.32.1 or newer if you use it. Older releases
  contain a separate proximity-crash vulnerability documented in
  [fivem#3727](https://github.com/citizenfx/fivem/issues/3727).

---

## Installation

1. Drop the `elit3-crashguard` folder into your server's `resources` directory.
2. Add this line to your `server.cfg`:

   ```cfg
   ensure elit3-crashguard
   ```

3. *(Optional)* enable Discord logging - see below.
4. Restart the server. You should see:

   ```
   Successfully Loaded | Protection Active | Discord Logging Off/On(depends if you got the webhook setup)
   ```

If OneSync is not enabled, the resource refuses to start

## Discord logging

Logging is configured entirely through convars in `server.cfg`. **The `set` lines
must appear above the `ensure elit3-crashguard` line**, because the webhook URL is
read once when the resource starts.

```cfg
set ecg_discord_webhook "https://discord.com/api/webhooks/XXXXXXXX/YYYYYYYY"
set ecg_discord_name "Elit3 Crash Guard"

ensure elit3-crashguard
```

| Convar | Default | Description |
|--------|---------|-------------|
| `ecg_discord_webhook` | *(empty = disabled)* | Discord webhook URL that receives one embed per blocked attempt |
| `ecg_discord_name` | `Elit3 Crash Guard` | Username shown for the webhook messages |


---
