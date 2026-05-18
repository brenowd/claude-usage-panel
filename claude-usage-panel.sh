#!/bin/bash
# Panel widget for Claude Code token usage
# Auto-detects output format: genmon (XFCE) or CommandRunner XML (Cinnamon)

detect_de() {
    case "${XDG_CURRENT_DESKTOP:-}" in
        *Cinnamon*|*X-Cinnamon*) echo "cinnamon"; return ;;
        *XFCE*) echo "genmon"; return ;;
    esac
    case "${GDMSESSION:-}" in
        cinnamon) echo "cinnamon"; return ;;
        xfce) echo "genmon"; return ;;
    esac
    pgrep -u "$USER" -x cinnamon-session >/dev/null 2>&1 && echo "cinnamon" && return
    pgrep -u "$USER" -x xfce4-session >/dev/null 2>&1 && echo "genmon" && return
    echo "genmon"
}
MODE=$(detect_de)

CONFIG_FILE="$HOME/.claude/.credentials.json"
CACHE_FILE="/tmp/claude-usage-cache.txt"
STATUS_CACHE="/tmp/claude-status-cache.txt"
CACHE_TTL=55
ICON="$HOME/.local/share/icons/claude/claude-robot.png"

xml_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    echo "$s"
}

get_token() {
    grep -o '"accessToken":"[^"]*"' "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f4
}

fetch_usage() {
    local token
    token=$(get_token) || return 1

    local body
    body=$(curl -s --max-time 5 "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-version: 2023-06-01" \
        -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null) || return 1
    [ -z "$body" ] && return 1
    echo "$body" | grep -q '"five_hour"' || return 1

    python3 - "$body" "$CACHE_FILE" <<'PY'
import json, sys, time, datetime
body = json.loads(sys.argv[1])
cache = sys.argv[2]

def iso_to_min(iso):
    if not iso: return 0
    t = datetime.datetime.fromisoformat(iso.replace('Z','+00:00')).timestamp()
    d = int(t) - int(time.time())
    return max(0, d // 60)

out = []
def field(prefix, obj):
    if not obj or obj.get('utilization') is None:
        out.append(f"{prefix}_pct=")
        out.append(f"{prefix}_min=")
        return
    out.append(f"{prefix}_pct={int(round(obj['utilization']))}")
    out.append(f"{prefix}_min={iso_to_min(obj.get('resets_at'))}")

field('s5h',  body.get('five_hour'))
field('s7d',  body.get('seven_day'))
field('opus', body.get('seven_day_opus'))
field('sonn', body.get('seven_day_sonnet'))

xu = body.get('extra_usage') or {}
out.append(f"extra_on={'1' if xu.get('is_enabled') else '0'}")
out.append(f"extra_pct={int(round(xu['utilization'])) if xu.get('utilization') is not None else ''}")

s5 = (body.get('five_hour') or {}).get('utilization', 0) or 0
out.append(f"status={'limited' if s5 >= 100 else 'allowed'}")

with open(cache, 'w') as f:
    f.write('\n'.join(out) + '\n')
print('\n'.join(out))
PY
}

# Fetch Anthropic status (Claude Code component, active incidents, upcoming maintenance)
fetch_status() {
    local body
    body=$(curl -sL --max-time 5 "https://status.anthropic.com/api/v2/summary.json" 2>/dev/null) || return 1
    [ -z "$body" ] && return 1

    python3 - "$body" "$STATUS_CACHE" <<'PY'
import json, sys, datetime, time

body = json.loads(sys.argv[1])
cache = sys.argv[2]

def sh_quote(s):
    if s is None: s = ''
    return "'" + str(s).replace("'", "'\\''") + "'"

# 1) Claude Code component status
cc = next((c for c in body.get('components', []) if c.get('name') == 'Claude Code'), None)
cc_status = (cc or {}).get('status', 'unknown')

# 2) Active incident (first unresolved)
incidents = body.get('incidents', [])
active = [i for i in incidents if i.get('status') not in ('resolved', 'postmortem')]
inc_name = inc_impact = inc_update = ''
if active:
    inc = active[0]
    inc_name = inc.get('name', '')
    inc_impact = inc.get('impact', 'none')
    updates = inc.get('incident_updates', [])
    if updates:
        body_txt = updates[0].get('body', '').strip()
        # Trim to first sentence-ish, max 140 chars
        if len(body_txt) > 140:
            body_txt = body_txt[:137].rstrip() + '...'
        inc_update = body_txt

# 3) Upcoming maintenance within 24h
maints = body.get('scheduled_maintenances', [])
maint_name = maint_iso = ''
now = datetime.datetime.now(datetime.timezone.utc)
horizon = now + datetime.timedelta(hours=24)
for m in maints:
    sf = m.get('scheduled_for')
    if not sf: continue
    t = datetime.datetime.fromisoformat(sf.replace('Z','+00:00'))
    if now <= t <= horizon:
        maint_name = m.get('name', '')
        maint_iso = sf
        break

out = [
    f"cc_status={sh_quote(cc_status)}",
    f"inc_name={sh_quote(inc_name)}",
    f"inc_impact={sh_quote(inc_impact)}",
    f"inc_update={sh_quote(inc_update)}",
    f"maint_name={sh_quote(maint_name)}",
    f"maint_iso={sh_quote(maint_iso)}",
]
with open(cache, 'w') as f:
    f.write('\n'.join(out) + '\n')
PY
}

# Convert minutes to human readable duration
human_duration() {
    local min=$1
    if [ "$min" -ge 1440 ]; then
        echo "$(( min / 1440 ))d $(( (min % 1440) / 60 ))h"
    elif [ "$min" -ge 60 ]; then
        echo "$(( min / 60 ))h $(( min % 60 ))m"
    else
        echo "${min}m"
    fi
}

# Absolute moment (pt-BR): "hoje às 15:30", "amanhã às 09:00", "qui 21/05 às 14:00"
human_when() {
    local min=$1
    local target=$(( $(date +%s) + min * 60 ))
    local today=$(date +%Y%m%d)
    local tomorrow=$(date -d 'tomorrow' +%Y%m%d)
    local tdate=$(date -d "@$target" +%Y%m%d)
    local thm=$(date -d "@$target" +"%H:%M")
    if [ "$tdate" = "$today" ]; then
        echo "hoje às $thm"
    elif [ "$tdate" = "$tomorrow" ]; then
        echo "amanhã às $thm"
    else
        local dows=(seg ter qua qui sex sáb dom)
        local dow=$(date -d "@$target" +%u)
        local dd=$(date -d "@$target" +%d/%m)
        echo "${dows[$((dow-1))]} $dd às $thm"
    fi
}

# Determine color based on percentage
colorize() {
    local pct=$1
    if [ "$pct" -ge 80 ]; then echo "red"
    elif [ "$pct" -ge 50 ]; then echo "orange"
    else echo "green"
    fi
}

# Use cache if fresh enough
HAVE_DATA=false
load_cache() { . "$CACHE_FILE" 2>/dev/null && HAVE_DATA=true; }
if [ -f "$CACHE_FILE" ] && [ $(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") )) -lt $CACHE_TTL ]; then
    load_cache
else
    if fetch_usage >/dev/null; then
        load_cache
    elif [ -f "$CACHE_FILE" ]; then
        load_cache
    fi
fi

if [ "$HAVE_DATA" = false ]; then
    [ -f "$ICON" ] && echo "<img>$ICON</img>"
    echo "<txt><span foreground='gray'>--</span></txt>"
    echo "<tool>Falha ao buscar uso</tool>"
    exit 0
fi

# Statuspage check (separate cache, same TTL)
cc_status= inc_name= inc_impact= inc_update= maint_name= maint_iso=
if [ -f "$STATUS_CACHE" ] && [ $(( $(date +%s) - $(stat -c %Y "$STATUS_CACHE") )) -lt $CACHE_TTL ]; then
    . "$STATUS_CACHE" 2>/dev/null
else
    fetch_status && . "$STATUS_CACHE" 2>/dev/null || [ -f "$STATUS_CACHE" ] && . "$STATUS_CACHE" 2>/dev/null
fi

# Color + label for the Claude Code component
case "$cc_status" in
    operational)         ap_hex='#98c379'; cc_pt='Operacional' ;;
    degraded_performance) ap_hex='#d19a66'; cc_pt='Degradado' ;;
    partial_outage)      ap_hex='#d19a66'; cc_pt='Indisponibilidade parcial' ;;
    major_outage)        ap_hex='#e06c75'; cc_pt='Indisponibilidade total' ;;
    under_maintenance)   ap_hex='#61afef'; cc_pt='Em manutenção' ;;
    *)                   ap_hex='#888888'; cc_pt='status indisponível' ;;
esac

# If there's an active incident, override color by impact severity
case "$inc_impact" in
    minor)    ap_hex='#d19a66' ;;
    major)    ap_hex='#e06c75' ;;
    critical) ap_hex='#e06c75' ;;
esac

session_pct=$s5h_pct
weekly_pct=$s7d_pct
sr_human=$(human_duration "$s5h_min")
wr_human=$(human_duration "$s7d_min")
sr_when=$(human_when "$s5h_min")
wr_when=$(human_when "$s7d_min")

s5_color=$(colorize "$session_pct")
s7_color=$(colorize "$weekly_pct")

# Map color names to hex
case "$s5_color" in
    red)    s5_hex='#e06c75' ;;
    orange) s5_hex='#d19a66' ;;
    green)  s5_hex='#98c379' ;;
esac
case "$s7_color" in
    red)    s7_hex='#e06c75' ;;
    orange) s7_hex='#d19a66' ;;
    green)  s7_hex='#98c379' ;;
esac

status_icon=""
case "$status" in
    limited)   status_pt="limitado"; status_icon=" ⚠" ;;
    allowed)   status_pt="permitido" ;;
    *)         status_pt="desconhecido" ;;
esac

# Per-model lines (only when API returns non-null)
model_lines=""
[ -n "$opus_pct" ] && model_lines+="
Opus (7d): ${opus_pct}% — reseta $(human_when "$opus_min")"
[ -n "$sonn_pct" ] && model_lines+="
Sonnet (7d): ${sonn_pct}% — reseta $(human_when "$sonn_min")"
[ "$extra_on" = "1" ] && [ -n "$extra_pct" ] && model_lines+="
Créditos extra: ${extra_pct}%"

# Status lines for tooltip
status_block="Claude Code: ${cc_pt}"
if [ -n "$inc_name" ]; then
    status_block+="
⚠ Incidente: ${inc_name}"
    [ -n "$inc_update" ] && status_block+="
   └ ${inc_update}"
fi
if [ -n "$maint_name" ] && [ -n "$maint_iso" ]; then
    maint_epoch=$(date -d "$maint_iso" +%s 2>/dev/null)
    if [ -n "$maint_epoch" ]; then
        maint_min=$(( (maint_epoch - $(date +%s)) / 60 ))
        [ "$maint_min" -lt 0 ] && maint_min=0
        status_block+="
⚙ Manutenção: ${maint_name} ($(human_when "$maint_min"))"
    fi
fi

if [ "$MODE" = "cinnamon" ]; then
    tooltip_val="Sessão (5h): ${session_pct}% — reseta ${sr_when} (em ${sr_human})
Semanal (7d): ${weekly_pct}% — reseta ${wr_when} (em ${wr_human})${model_lines}
Status conta: ${status_pt}${status_icon}
${status_block}"
    tooltip_val=$(xml_escape "$tooltip_val")
    echo '<xml>'
    echo '  <appsettings>'
    echo "    <tooltip>${tooltip_val}</tooltip>"
    echo '    <clickaction>xdg-open https://claude.ai/settings/usage</clickaction>'
    echo '  </appsettings>'
    echo '  <item>'
    echo '    <type>box</type>'
    if [ -f "$ICON" ]; then
        echo '    <item>'
        echo '      <type>icon</type>'
        echo "      <value>$(xml_escape "$ICON")</value>"
        echo '    </item>'
    fi
    echo '    <item>'
    echo '      <type>text</type>'
    echo "      <value>●</value>"
    echo '      <attr>'
    echo "        <style>color: ${ap_hex};</style>"
    echo '      </attr>'
    echo '    </item>'
    echo '    <item>'
    echo '      <type>text</type>'
    echo "      <value> 🜁 $(xml_escape "${session_pct}%")</value>"
    echo '      <attr>'
    echo "        <style>color: ${s5_hex};</style>"
    echo '      </attr>'
    echo '    </item>'
    echo '    <item>'
    echo '      <type>text</type>'
    echo "      <value> $(xml_escape "${sr_human}")</value>"
    echo '      <attr>'
    echo '        <style>color: gray;</style>'
    echo '      </attr>'
    echo '    </item>'
    echo '    <item>'
    echo '      <type>text</type>'
    echo '      <value> | </value>'
    echo '      <attr>'
    echo '        <style>color: gray;</style>'
    echo '      </attr>'
    echo '    </item>'
    echo '    <item>'
    echo '      <type>text</type>'
    echo "      <value> 🜃 $(xml_escape "${weekly_pct}%")</value>"
    echo '      <attr>'
    echo "        <style>color: ${s7_hex};</style>"
    echo '      </attr>'
    echo '    </item>'
    echo '  </item>'
    echo '</xml>'
else
    [ -f "$ICON" ] && echo "<img>$ICON</img>"
    echo "<txt><span foreground='$ap_hex'>●</span> <span foreground='$s5_hex'>🜁 ${session_pct}%</span><span foreground='gray'> ${sr_human}</span><span foreground='gray'> | </span><span foreground='$s7_hex'>🜃 ${weekly_pct}%</span></txt>"
    echo "<tool>Sessão (5h): ${session_pct}% — reseta ${sr_when} (em ${sr_human})
Semanal (7d): ${weekly_pct}% — reseta ${wr_when} (em ${wr_human})${model_lines}
Status conta: ${status_pt}${status_icon}
${status_block}</tool>"
    echo "<txtclick>xdg-open https://claude.ai/settings/usage</txtclick>"
fi
