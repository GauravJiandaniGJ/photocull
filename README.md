# PhotoCull

Personal iPhone photo-culling app. Finds near-duplicate shots of the same moment, picks the best one, flags WhatsApp/screenshot clutter, lets you review every decision, then moves the losers to Recently Deleted in one tap. On-device only; no server, no iCloud.

- `PHOTOCULL_SPEC.md` — the full spec (source of truth)
- `CLAUDE.md` — build/test commands, architecture, safety rules
- `Packages/PhotoCullCore` — pure-Swift classifier, grouper, scorer (`swift test`)
- `PhotoCull/` — SwiftUI app target; `xcodegen generate` builds the project from `project.yml`
