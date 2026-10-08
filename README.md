# resolve-file-bridge

[English](#resolve-file-bridge) · [עברית](#עברית)

Run Lua **inside a running DaVinci Resolve** from outside it - including the **free** version - through
plain files. Built so an AI agent (or any script) can inspect and edit Fusion comps, render test frames,
read and build timelines, and queue renders, while you keep working in Resolve.

```
 your script / AI agent                         DaVinci Resolve (Fusion Lua)
 ─────────────────────                          ────────────────────────────
 bridge.py / mcp_server.py ──► inbox/cmd_000042.lua ──► resolve_bridge.lua runs it
                         ◄── outbox/cmd_000042.comp ◄── result saved as JSON (hex) in a comp file
```

## Why files?
Resolve's external scripting API (connecting from another process) is, as far as we know, limited to Resolve
Studio. The scripting console *inside* Resolve works in the free version too, but its Lua is sandboxed: no `io`, no `os.remove`, no directory listing. It can `dofile()`
a script, check `bmd.fileexists()`, and save a comp. That is exactly enough:

- commands are numbered Lua files the listener finds by number (no listing needed);
- results are encoded as JSON → hex, stored in the comp's CustomData and written with `comp:Save()`;
- the client archives finished pairs and writes `state.lua` so a restarted listener resumes at the right number.

No network, no ports, nothing installed into Resolve except one script in the Scripts menu.

## What's in the repo
| Path | What |
|---|---|
| `resolve/resolve_bridge.lua` | the listener (runs inside Resolve) |
| `resolve/Resolve Bridge Listen.lua` | Scripts-menu launcher template (the installers generate a ready one) |
| `install.bat` / `install.ps1` / `install.sh` | one-step install (and uninstall) |
| `client/bridge.py` | Python client + CLI (standard library only) |
| `client/mcp_server.py` | MCP server: `resolve_ping`, `resolve_run_lua`, `resolve_list_nodes`, `resolve_render_frames`, `resolve_timeline_info` |
| `skill/resolve-bridge/SKILL.md` | agent skill: safe workflow, verification, Fusion/Resolve gotchas |
| `AGENTS.md` / `CLAUDE.md` | orientation for agents opened in this folder |
| `examples/` | ping, list nodes, add node + render, timeline info, cut list → timeline, queue a render |

## Quick start
Put this folder somewhere local and run **`install.bat`** (Windows) or **`./install.sh`** (macOS/Linux) -
see [INSTALL.md](INSTALL.md). Restart Resolve, start **Workspace > Scripts > Resolve Bridge Listen**, then:

```bash
export RESOLVE_BRIDGE_ROOT=/path/to/resolve-file-bridge     # Windows: set RESOLVE_BRIDGE_ROOT=C:\resolve-file-bridge
python client/bridge.py ping
python client/bridge.py exec "result = bridge.dump()"
python client/bridge.py run examples/04_timeline_info.lua
```

In a command, `comp` is the current Fusion comp, `bridge` holds helpers (see SKILL.md), `print()` output is
captured, and whatever you assign to the global `result` comes back as JSON. Each command is one undo step.

## Using it with an AI agent
The installer can register the MCP server with Claude Desktop / Claude Code and install the agent skill,
so a new conversation already has `resolve_*` tools and knows the rules. Other MCP clients: point them at
`client/mcp_server.py` (see INSTALL.md); agents working inside this folder pick up `AGENTS.md` / `CLAUDE.md`.

Then just ask, e.g.:
- *"Check the Resolve bridge is connected and tell me what's in my current Fusion comp."*
- *"Render frames 100, 500 and 900 of MediaOut1 and tell me if the text is readable."*
- *"Build a new timeline from my interview clip without the long pauses, put a marker on every cut."*
- *"Queue an H.264 render of the current timeline to my Desktop as project_v2."*

Keep Resolve open with **Resolve Bridge Listen** running while the agent works.

## Known limitations
- Results are written by saving a short-lived temporary comp. If that fails the listener falls back to
  saving your open comp, which renames it to `cmd_NNNNNN.comp` (cosmetic).
- Every Fusion `comp:Render` shows a "Render completed" dialog.
- Resolve API calls can return nil while a modal dialog is open - resend.
- One client at a time; ~0.5 s latency per command (poll interval).
- Results go out via `comp:Save`; very large results (MBs) are slow - write images to `renders/` instead.
- Verified on Windows with the free version of Resolve: commands on the Fusion and Edit pages, media pool
  reading, building a timeline from a cut list, render queue. macOS/Linux should work (path separators
  are auto-detected) but are untested - reports welcome.

## Security
The listener executes **any** Lua file that appears in its inbox, with full access to Resolve and your
projects. Keep the folder local and private. See [SECURITY.md](SECURITY.md).

## License
MIT

---

<div dir="rtl">

## עברית

הכלי **resolve-file-bridge** מאפשר להריץ קוד Lua **בתוך DaVinci Resolve פתוח** - גם בגרסה **החינמית** - מתוך תוכנה חיצונית, דרך קבצים רגילים.
הוא נבנה כדי שסוכן בינה מלאכותית (כמו Claude) או כל סקריפט יוכלו לבדוק ולערוך קומפוזיציות Fusion, לרנדר פריימים לבדיקה,
לקרוא ולבנות טיימליינים ולהפעיל רינדורים - בזמן שאתם ממשיכים לעבוד ב-Resolve.

### למה דרך קבצים?
ממשק הסקריפטים החיצוני של Resolve מוגבל (ככל הידוע לנו) לגרסת Studio. קונסולת הסקריפטים *שבתוך* Resolve עובדת גם בגרסה החינמית,
אבל ה-Lua שלה מוגבל: אין גישה לקבצים, אין מחיקה ואין רשימת תיקיות. היא כן יכולה להריץ סקריפט, לבדוק אם קובץ קיים ולשמור קומפוזיציה - וזה מספיק:
הפקודות נכתבות כקבצי Lua ממוספרים לתיקיית `inbox`, והתוצאות חוזרות כ-JSON בתוך קובץ קומפוזיציה בתיקיית `outbox`.
אין רשת, אין פורטים, ולא מותקן כלום בתוך Resolve מלבד סקריפט אחד בתפריט Scripts.

### התקנה
1. הורידו את התיקייה למקום מקומי במחשב (עדיף נתיב באנגלית, למשל `C:\resolve-file-bridge`).
2. ב-Windows הריצו **`install.bat`** (ב-macOS / Linux: `./install.sh`). המתקין:
   - יוצר את תיקיות העבודה ומתקין את סקריפט ההפעלה בתפריט Scripts של Resolve;
   - מגדיר את המשתנה `RESOLVE_BRIDGE_ROOT`;
   - מציע (שאלות כן/לא) לרשום את שרת ה-MCP ב-Claude Desktop וב-Claude Code ולהתקין את ה-skill לסוכן.
3. הפעילו מחדש את Resolve, פתחו פרויקט והפעילו **Workspace > Scripts > Resolve Bridge Listen**.
4. בדיקה: `python client/bridge.py ping` - אמור להחזיר `"status": "OK"`.
5. עצירה: `python client/bridge.py stop`.

### שימוש עם סוכן AI
אחרי ההתקנה, שיחה חדשה עם Claude כבר מכירה את כלי `resolve_*` ואת כללי הבטיחות. פשוט בקשו, למשל:
- *"בדוק שהגשר ל-Resolve מחובר ותגיד לי מה יש בקומפוזיציית ה-Fusion הנוכחית."*
- *"רנדר את פריימים 100, 500 ו-900 ותגיד לי אם הכיתוב קריא."*
- *"בנה טיימליין חדש מהראיון בלי ההפסקות הארוכות, עם מרקר על כל חיתוך."*

ה-skill (`skill/resolve-bridge/SKILL.md`) מנחה את הסוכן לבנות לצד העבודה שלכם, לאמת כל שינוי עם פריימים מרונדרים,
ולא לשנות את הפלט הסופי, למחוק נודים או לדרוס רינדור קיים בלי לשאול.

### אבטחה
המאזין מריץ **כל** קובץ Lua שמגיע לתיקיית ה-inbox, עם גישה מלאה ל-Resolve ולפרויקטים שלכם.
שמרו את התיקייה מקומית ופרטית (לא בתיקייה מסונכרנת לענן או משותפת), והפעילו את המאזין רק כשצריך. פרטים ב-[SECURITY.md](SECURITY.md).

### רישיון
חופשי לשימוש, שינוי והפצה (רישיון MIT).

</div>
