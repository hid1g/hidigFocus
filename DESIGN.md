---
name: "hidigFocus — Print"
description: "Native SwiftUI/AppKit implementation of the approved Paper/Ink linocut identity. Data schema remains version 3; UI acceptance and performance evidence are separate."
colors:
  light-canvas: "#F7F3EA"
  light-surface: "#FFFDF7"
  light-text: "#203747"
  light-secondary: "#67716F"
  light-accent: "#BC492F"
  dark-canvas: "#1C2B36"
  dark-surface: "#253844"
  dark-text: "#EEE9DF"
  dark-secondary: "#B6C0C1"
  dark-accent: "#EC9877"
  sidebar: "#17384D"
typography:
  family: "Golos Text"
  alternatives: "Onest, Manrope, Inter; legacy native fonts retained"
---

# hidigFocus — Print

Approved visual reference: hidigFocus-design-package, version 1.0, 31 October 2026.
The native implementation remains the authority for behavior, data and system affordances.

## Identity and resources

Warm ivory work surfaces, deep ink navigation and restrained vermilion actions. Engraved texture
belongs only to the application icon. Task/list colors remain user data and are never replaced
by the interface palette. Paper, Ink, Mist and Moss have adaptive light/dark appearances;
legacy palette and font identifiers remain readable and selectable.

Golos Text is the default. Onest, Manrope and Inter are bundled as native TTF fonts with OFL
licenses in Sources/Resources/Fonts. Registration is process-local, cached, with a system fallback.
Native navigation symbols support outline, tile and hierarchical two-tone variants. Doors and
Medallion are independent high-resolution transparent resources in Resources/PrintIcons,
not crops of the concept contact sheet. Previous icon choices remain in settings and Dock resources.

## Components and layout

Theme.swift owns button, field, selection, checkbox, panel and menu styles. PrintDesign.swift
owns migration, shared durations, icon-pack preferences and empty-state presentation.
Buttons preserve native keyboard semantics. Custom selections expose selected traits and values.
System menus, file panels, date input and permission dialogs remain native.

Core radii: event 4pt, control 5pt, panel 7pt; the existing anchored task editor retains its native
14pt radius. Sizes: buttons 32pt, icon buttons 32pt, compact native variants where required.
The main window supports 760pt width. Navigation collapses automatically below 1000pt without
rewriting the user's stored expanded width. Settings switches to a single column when its live
preview cannot fit. Narrow habit tables reduce day-column width and move streak information
into the name area. Kanban columns retain horizontal scrolling.

Calendar geometry is unchanged: minutes / 60 × saved hour height. Defaults do not overwrite an
existing 120pt/hour setting. Short titles/time adapt inside that geometry; a long title cannot
lengthen an event. Full labels remain in task details and accessibility descriptions.

## Motion and state

Hover/press: 120ms; state/navigation opacity: 180ms; navigation-width transition: 240ms.
Reduce Motion removes scaling and spatial animations while retaining state feedback. Direct
calendar gestures disable implicit animation; existing frame clock, interruption tracking,
viewport retention and 15-minute committed grid remain authoritative. Resize affordances appear
on hover/drag instead of remaining visible on every event.

FocusPresentationState shares idle task/mode/phase between the main and compact focus windows,
without publishing or serializing the entire task store. Settings category and statistics period
retain their presentation preferences. Existing planner scroll positions/projections stay intact.

## Data contract

First launch applies only Paper/Golos/Doors/two-tone once, after retaining prior appearance keys.
Appearance mode, text size, calendar scale, dates, task IDs, series, lists and task colors remain
unchanged. PersistedAppState stays schema 3. A failed database load blocks editing and services;
a failed final write blocks normal termination. Saved status follows committed revisions.
SQLite backups use its online backup mechanism, including WAL. Legacy JSON imports keep the
original backup and store the upgraded snapshot rather than rewriting its old payload.

QA uses its own bundle ID, preference domain, data root and attachment root. Network, blocking,
login registration and notifications are disabled. Production installation is a separate step.

## Verification boundary

See Docs/PrintDesign-Implementation-2026-10-31.md and the implementation artifact reports.
A screenshot, unit suite or data benchmark is not an FPS, input latency or VoiceOver certificate.
Real integrations and macOS 13 runtime need their own acceptance environments.


## 1 November control refinement

Ordinary action styles share 32 pt height, 12 pt horizontal inset and 5 pt radius. Optional full-width mode is used by dialog choices and paired fill actions. Native filter/sort trigger labels and standard date/time/menu controls share geometry and 13 pt type. Expanded navigation has one 32 pt logo/title/toggle row; compact and expanded states keep navigation at the same vertical position.

Recurring delete confirmation uses a 340 pt panel with 24 pt padding, 11 pt radius and three 292 pt actions. Cancel retains native visible keyboard focus. The editor event monitor gives the overlaid confirmation priority and preserves the editor when cancellation is chosen.

## Approved unified window toolbar — 1 November

The main scene uses a native titled window and unified toolbar with the native window title hidden. Standard window buttons, one navigation action and the current section/date heading occupy the system toolbar above the sidebar. Content no longer ignores the titlebar safe area. The calendar title includes the day, long Russian month and year in the planner time zone. Sidebar branding has no duplicate navigation control.

Below 1000 pt, the toolbar action presents navigation over the existing compact rail without changing calendar content width; selecting a different section or clicking the scrim dismisses it. Wider windows retain the saved expanded width and normal collapse behavior.

Task hierarchy disclosure has a complete rectangular 32×32 pt hit target; its small chevron is only the visual mark. Selection, completion and title remain independent controls. Semantic status colors are independent of the interface accent: green for active, red for inactive, accompanied by text. Light colors maintain at least 3:1 against both Paper and the ink sidebar.
