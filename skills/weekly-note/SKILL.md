---
name: weekly-note
description: Weekly Obsidian scratchpad changeover. Creates this week's note (Mon–Fri) in the `notes` vault with a "Last week" summary of the previous note, carried-over open to-dos, and empty daily headings. Use when the user asks to start/roll over/set up the weekly note or notes for the week.
---

# Weekly Note Changeover

Creates the new weekly scratchpad in the Obsidian vault `notes` (`~/dev/notes`) using the `obsidian` CLI. It summarizes last week's note and adds empty daily headings.

## Conventions (match these exactly)
- Path: `Scratchpads/<YYYY>/<MM> - <Month>/<Mon YYYY-MM-DD> to <Fri YYYY-MM-DD>.md`. The folder is based on **Monday's** date, e.g. `Scratchpads/2026/09 - September/2026-09-28 to 2026-10-02.md`.
- Sections are H2 (`## Personal`, `## Last week (...)`). Days are H1 (`# Mon Sept 28`).
- Day labels: `Mon`, `Tues`, `Wed`, `Thurs`, `Fri`. Month: `Sept` for September, otherwise match whatever the previous note uses (e.g. `Oct`).
- Nested bullets use tabs. Tasks use `- [ ]` / `- [x]`.

## Workflow

### 1. Compute the target week (never assume the date)
```bash
dow=$(date +%u)   # 1=Mon … 7=Sun; on a weekend, target the upcoming week
if [ "$dow" -ge 6 ]; then mon=$(date -v+$((8-dow))d +%Y-%m-%d); else mon=$(date -v-$((dow-1))d +%Y-%m-%d); fi
fri=$(date -j -v+4d -f %Y-%m-%d "$mon" +%Y-%m-%d)
folder="Scratchpads/$(date -j -f %Y-%m-%d "$mon" +%Y)/$(date -j -f %Y-%m-%d "$mon" '+%m - %B')"
target="$folder/$mon to $fri.md"
echo "today=$(date +%F) target=$target"
for i in 0 1 2 3 4; do date -j -v+"$i"d -f %Y-%m-%d "$mon" '+%a %b %-d'; done   # day headings, then relabel per conventions
```
If the user names a specific week, use its Monday instead.

### 2. Find and read last week's note
- `obsidian files folder=Scratchpads` → take the **latest filename that sorts before** `$mon`. Don't compute its name, because past notes don't always end on Friday (e.g. `2026-09-14 to 2026-09-19`).
- `obsidian read path="<that path>"`
- If the target already exists, stop and ask. Never pass `overwrite`. The CLI exits 0 even for a missing file, so check the output instead: `obsidian read path="$target" 2>&1 | grep -q 'not found'` means it doesn't exist.

### 3. Draft the new note
```markdown
## Personal
<unchecked/plain personal to-dos from last week, as - [ ] tasks>

## Last week (<Mon d>–<Fri d>)
**Done**
- <concise bullets: completed items, meetings/1:1s held, PRs opened/merged, decisions, takeaways>

**Carried over**
- [ ] <every unchecked work task and unresolved next step>

**Notes**
- <ideas / advice / context worth remembering; omit section if none>

# Mon <Month d>


# Tues <Month d>


# Wed <Month d>


# Thurs <Month d>


# Fri <Month d>
```
Rules:
- **Summarize, don't copy.** Condense each day's notes into outcomes. Link long reference material (setup guides, runbooks) back to last week's note instead of copying it, e.g. `[[<last note name>]]`.
- **Carried over = open items only.** Include `- [ ]` tasks and "next steps" not marked done. Don't mark anything done unless the note (or a checked source) says it is.
- Keep `[[wikilinks]]` intact.
- Keep security/cleanup reminders (key rotation, break-glass access, temp files) as open items until the note confirms they're done.
- Optional: enrich with ticket IDs or PR numbers from Linear/GitHub. Tell the user which details came from outside the note.
- Leave out PHI and secrets, even if last week's note contains them.

### 4. Create it with the Obsidian CLI
The CLI takes content as one argument with `\n` for newlines and `\t` for tabs. Write the draft to a temp file and convert:
```bash
tmp=$(mktemp); cat > "$tmp" <<'EOF'
<draft>
EOF
content=$(awk 'BEGIN{ORS="\\n"}{gsub(/\t/,"\\t"); print}' "$tmp")
obsidian create path="$target" content="$content"
```
Don't modify last week's note.

### 5. Verify
- `obsidian read path="$target"` should match the draft (`diff` against `$tmp`), then `rm "$tmp"`.
- `grep -n '^#' ~/dev/notes/"$target"` should show Personal, Last week, and the 5 day headings. Don't use `obsidian outline`, which reads the active file and ignores `path`.

### 6. Report
Give the path and a short summary of what went into Done and Carried over. Flag anything to double-check: items carried over because their status was unclear, details pulled from outside the note, and the folder choice if the week spans two months.
