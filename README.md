# pbalab External Watchdog — Out-of-Band Uptime Monitoring

A small out-of-band watchdog that runs on my Oracle Cloud node in Phoenix and
watches my home server (`pbalab`) in Waco. If the home server goes offline,
the alert fires **from Phoenix** — because the watcher lives outside the system
it monitors.

## The problem it solves

All of my primary monitoring (Prometheus, alerting, log triage) runs *on* the
home server it monitors. That creates a blind spot: if the home server loses
internet, the very system that would alert me is the system that just went
offline. I would only see alerts later, once connectivity returned — by which
point I already knew something was wrong.

This is a classic monitoring anti-pattern: **you cannot reliably monitor a
system from inside that system.**

## The approach

This watchdog runs on a separate node, in a separate region, with its own
independent internet connection. It checks the home server's status-page
endpoint over a Tailscale mesh every 2 minutes. The logic is inverted from
normal monitoring — instead of the home server reporting "I'm fine" and going
silent when it isn't, **silence from the home server becomes the alert**,
detected by an external observer.

- Runs on the Phoenix (Oracle Cloud) node — watches the Waco home server,
  the reverse of the normal scrape direction
- Checks the home server's Kubernetes status page over Tailscale every 2 min
  (via cron)
- Requires **2 consecutive failures** before alerting, so a momentary network
  blip doesn't cry wolf
- Alerts a dedicated Discord channel on the DOWN transition, and sends a single
  recovery message on the UP transition — alerts on state change only, never
  spams while down
- Alert-only by design — it does not auto-remediate

## State machine
- home server reachable    → reset failure counter; if previously DOWN, send recovery

- home server unreachable   → increment failure counter

- counter >= 2 AND was UP → send DOWN alert, mark DOWN

State is tracked in two files in the home directory (`.pbalab_watcher_state`
and `.pbalab_watcher_fails`), so the script is stateless between cron runs and
remembers whether it has already alerted.

## Security

- The Discord webhook URL is loaded from `~/.watcher_env` (chmod 600), never
  hardcoded in the script and never committed to git
- State files live in the home directory, outside this repo

## Deployment

```bash
# On the external (Oracle) node:
cp pbalab-watcher.sh ~/scripts/pbalab-watcher.sh
chmod +x ~/scripts/pbalab-watcher.sh

# Create the secret file:
echo 'DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."' > ~/.watcher_env
chmod 600 ~/.watcher_env

# Schedule it every 2 minutes:
crontab -e
# */2 * * * * /bin/bash /home/ubuntu/scripts/pbalab-watcher.sh >> /home/ubuntu/pbalab-watcher.log 2>&1
```

## Stack

Bash · cron · curl · Tailscale · Discord webhooks · Oracle Cloud
