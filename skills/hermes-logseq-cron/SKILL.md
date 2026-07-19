---
visibility: public
name: hermes-logseq-cron
description: Cron job patterns for Hermes Agent + Logseq — check-ins, research pipelines, publishing, and read-back workflows.
version: 1.0.0
metadata:
  hermes:
    tags: [logseq, cron, check-in, publishing, hermes]
---

# Hermes Logseq — Cron Patterns

How to wire Hermes cron jobs to your Logseq knowledge graph for check-ins, research pipelines, and automated publishing.

## Design Principles

1. **Journals are the daily state.** Write cron output to journals, not isolated date-prefixed pages.
2. **Read before you write.** Every cron job reads the user's recent journal edits first.
3. **Desktop vs headless doesn't matter.** Both modes produce the same file structure — the cron job just reads/writes markdown.
4. **Don't pollute tags.** Use entity schemas with `type::` properties for structured data, not ad hoc hashtags.

## Publishing to the Graph

### Script (simple content)

```bash
python3 ~/.hermes/skills/hermes-logseq/scripts/logseq-publish.py \
  --title "2026-07-19 - Research: Net Art" \
  --tags "cryptoart, research, net-art" \
  --content "Content here"
```

**Flags:**
- `--title` (required) — page title
- `--tags` — comma-separated tags (written to `tags::` property)
- `--content` — page body. Omit to read from stdin
- `--no-publish` — write file but don't git push

### Direct write (nested/complex content)

The publish script double-prefixes every line, which breaks nested block formatting. For anything with indentation levels:

```python
from hermes_tools import write_file, terminal

content = """title:: Research Results
tags:: #research #topic
- Key finding one
	- Supporting detail
	- Another detail
- Key finding two
"""

write_file(path="~/my-graph/pages/Research Results.md", content=content)
terminal("cd ~/my-graph && git add -A && git commit -m 'research results' && git push")
```

## Block Format Reference

```markdown
title:: Page Title
tags:: [[Parent]] #tag1 #tag2
- Top-level block #topic
	- Child block (tab-indented)
		- Grandchild (double tab)
- Another block
```

**Rules:**
- Every content line starts with `- `
- Tabs for indentation, never spaces
- `title::` and `tags::` on first line — no dash, no YAML `---`
- Blank lines between blocks are fine

## Check-In Patterns

### Morning Kickoff

**What to read:**
1. Yesterday's journal (`journals/YYYY_MM_DD.md`)
2. Yesterday's EOD page (look for "Tomorrow" section)
3. Yesterday's afternoon summary page

**What to write:**
- Today's morning kickoff as a page: `pages/YYYY-MM-DD - Morning Kickoff.md`
- Include: context from yesterday, today's priorities, any blockers

### Afternoon Summary

**What to read:**
1. Today's morning kickoff page
2. Today's morning check-in page (if it exists)
3. Today's journal
4. Git diff to detect user's handwritten edits

**What to write:**
- Afternoon summary page: `pages/YYYY-MM-DD - Afternoon Summary.md`
- Include: what got done, what shifted, suggestions for evening

### EOD Check-In

**What to read:**
1. Today's afternoon summary
2. Today's morning kickoff
3. Today's journal

**What to write:**
- Brief EOD note — completions, energy level, tomorrow's seeds

### Detecting User Edits

```bash
# Find what changed today
git diff --name-only --since="2026-07-19T00:00:00" HEAD

# Diff specific file to see handwritten content
git diff HEAD~5 HEAD -- journals/2026_07_19.md
```

Don't filter by commit message — Logseq desktop generates "Auto saved" commits that bury meaningful edits.

## Research Pipeline Pattern

For automated research crons (e.g., daily topic scans):

1. **Read:** Check for new research priorities from user's journal
2. **Research:** Web search on the topic
3. **Write:** Create a research page with findings
4. **Deliver:** Brief summary to Telegram/chat, full content in graph

```markdown
title:: 2026-07-19 - Topic Research
tags:: [[Research]] #topic-name

- ## Finding: Something Interesting
	- Source: URL
	- Key point here
- ## Finding: Another Thing
	- Source: URL
- ## Sources Checked But Not Cast
	- URL 1 — reason for skipping
	- URL 2 — reason for skipping
```

## Content Writing Patterns

### Entity Schemas

For structured data (jobs, services, research topics), use typed blocks:

```markdown
- Job Title
	type:: job
	company:: Company Name
	status:: backlog
	source:: URL
	salary-low:: 80000
	salary-high:: 120000
```

Types to define based on your use case. Common ones: `job`, `service`, `research-topic`, `daily-standup`, `digest`.

### Tag Philosophy

Tags create navigable pages. Use sparingly:

**Good:** `#cryptoart`, `#build-what-you-use`, `#dogfooding` — concepts worth browsing
**Bad:** `#agent-infrastructure`, `#request-flow` — dead-end pages nobody visits

Not every block needs a tag. Many are self-explanatory through `[[]]` links and hierarchy.

## Cron Configuration

Example cron job for a morning kickoff:

```yaml
cronjob:
  - name: morning-kickoff
    schedule: "0 7 * * 1-5"  # 7am weekdays
    prompt: |
      Read the user's graph state and generate a morning kickoff.
      1. Read yesterday's journal and EOD page
      2. Detect any handwritten edits
      3. Write today's kickoff page
      4. Deliver brief summary
    skills: [hermes-logseq, hermes-logseq-cron]
    toolsets: [terminal, file, web]
    workdir: /path/to/your/graph
```

**Tip:** Set `workdir` to your graph directory so all file operations default there.

## Merge Conflict Recovery

If git pull hits a conflict (desktop and server both edited):

```bash
cd /path/to/graph
git stash
git pull --quiet
git checkout --theirs <conflicted-file>  # prefer desktop edits
git add <conflicted-file>
git stash pop 2>/dev/null
```

The human's handwriting always wins over cron output.
