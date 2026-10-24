# Changelog

## 1.6.2

- Extend manual and scheduled Night Light controls down to 1600 K.

## 1.6.1

- Save Night Light schedule preferences in the plugin's gitignored
  `settings.json` instead of the runtime state directory.
- Continue reading the former state file as a migration fallback.
- Replace stale or competing Hyprsunset processes with one healthy instance and
  verify that manual temperature changes take effect before updating the menu.

## 1.6.0

- Add an optional daily Night Light schedule with editable start and end times.
- Preserve and restore the preexisting Hyprsunset configuration when the
  schedule is enabled or disabled.
- Skip automatic profile application when the live layout already matches and
  avoid rewriting identical monitor rules, preventing reload/notification loops.

## 1.5.0

- Redesign the panel around Omarchy's native vertical layout and stock controls.
- Keep brightness sliders for every active display at the top of the menu.
- Add Night Light on/off and an expandable color-temperature control to the
  Display panel.
- Collapse the visual arrangement canvas behind an Arrange displays button.
- Give every connected monitor its own scale and expandable advanced-settings
  section.

## 1.4.3

- Write the last verified per-display rules into the Hyprland monitor config so
  the arrangement is restored synchronously during every configuration reload.

## 1.4.2

- Preserve verified arrangements across Hyprland configuration reloads by
  retiring Omarchy's automatic catch-all monitor rule after the plugin takes
  ownership of a layout.
- Recheck the automatic profile when Hyprland reports a configuration reload,
  even when the connected-display topology has not changed.

## 1.4.1

- Show friendly hardware names in the full-screen Identify overlays.

## 1.4.0

- Apply arrangement and per-display setting changes automatically.
- Replace the preview confirmation flow with an Undo button that restores the
  previous verified layout.
- Make Undo track brightness changes as well as layout and per-display setting
  changes, so it always reverses the most recent panel action.
- Coalesce rapid changes and continue using crash-safe rollback while each
  modeset is verified.
- Stage fractional scale changes at an automatic position before restoring the
  requested attached edge, matching Omarchy's native scaling behavior.
- Release Omarchy's numeric catch-all monitor scale when it would override an
  explicitly chosen internal-display scale every two seconds.

## 1.3.1

- Show friendly hardware names in the panel, including Apple Studio Display
  and Built-in Display, while retaining connector IDs internally.

## 1.3.0

- Show an always-expanded brightness slider for every controllable display.
- Put each display's UI/text scale beside its brightness control.
- Remove the global text-size control and explanatory copy.
- Collapse resolution, refresh, orientation, mirroring, and connection controls
  behind a compact More settings button.
- Tighten panel spacing and the arrangement canvas.

## 1.2.2

- Suspend automatic profile matching while a layout preview is waiting for
  confirmation, preventing an older profile from replacing it early.
- Serialize helper operations so preview, profile matching, confirmation, and
  rollback cannot race when display changes rebuild shell surfaces.

## 1.2.1

- Rename Apply to Preview and keep the countdown, Revert, and Keep changes
  controls in the fixed action row so confirmation cannot fall below the view.
- Extend the preview window to 20 seconds.
- Let the crash-safe systemd timer perform timeout recovery without racing a
  second QML-triggered rollback process.

## 1.2.0

- Keep dragged displays attached to the nearest non-overlapping display edge.
- Require the complete extended-desktop layout to be edge-connected before it
  can be applied or saved.
- Reattach a selected display after changing its resolution, scale, or
  orientation.

## 1.1.3

- Anchor the panel below the Display bar icon, matching Omarchy's stock panels.

## 1.1.2

- Leave the unused panel IPC target empty so per-monitor widget construction
  cannot briefly register duplicate handlers.

## 1.1.1

- Keep display identification inside the bar widget so Omarchy's Display
  shortcut opens the settings panel.
- Disable the redundant per-screen IPC handler; Omarchy routes bar-widget
  panels to the focused display directly.

## 1.1.0 — Display Settings derivative

- Replace the stock `omarchy.monitor` widget instead of adding a second bar
  icon.
- Integrate Omarchy's focused-display brightness control.
- Integrate Omarchy's global text-size slider and label its session-wide scope.
- Add magnetic edge and alignment snapping to the visual arrangement canvas.
- Label compositor scale as a per-display setting and explain that it is the
  supported way to change interface and text size independently by output.
- Move state and rollback units to the `omarchy-display-settings` namespace.
- Retain the audited upstream layout validation, live-state verification,
  15-second rollback, and topology profile implementation.

## 1.0.3

- Keep a separate automatic `Default` profile for every connected display
  topology instead of replacing defaults saved for other docks or monitor sets.
- Verify position, orientation, mirroring, enabled state, mode, refresh rate,
  and scale after applying a layout.
- Restore the complete previous layout when a preview, automatic profile, or
  rollback-scheduler operation fails.
- Report confirmation, restoration, and profile-save failures accurately in
  the panel, and retry automatic profile matching after transient failures.
- Reject duplicate outputs, overlapping layouts, malformed modes, and invalid
  mirror targets before changing display state.
- Add automated manifest, helper, model, shell syntax, and CI checks.

## 1.0.2

- Verify resolution, refresh rate, and scale after Hyprland applies a layout.
- Report hardware-rejected display modes instead of saving them as successful.
- Automatically restore the previous layout when post-apply verification fails.

## 1.0.1

- Bound the popup to a responsive 760-pixel viewport instead of scaling its
  design dimensions with the global text-size preference.
- Reworked header, settings, action, and confirmation rows with responsive
  layouts so controls remain balanced and readable at large text sizes.
- Fixed preview completion handling so successful scale and layout changes
  present the confirmation controls instead of silently rolling back.
- Apply monitor changes through Hyprland's current Lua `hl.monitor` API; the
  legacy `keyword monitor` path could report success without changing state.
- Present a display's sole advertised resolution as its disabled native mode,
  while keeping distinct refresh rates selectable.
- Normalize EDID mode labels before calling Hyprland so values such as
  `3440x1440@59.97Hz` apply as native modes instead of silently falling back.
- Removed the illustrative preview while an accurate application screenshot is
  prepared.

## 1.0.0

- Initial release with visual display arrangement, per-display mode, rotation,
  scale, mirroring, safe rollback, identification, and topology profiles.
