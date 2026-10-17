/*
 * Spicetify Fixes
 * Version: 1.0.0
 * Author:  VoidCrowned
 * Repo:    https://github.com/VoidCrowned/spicetify-fixes
 * Licence: WTFPL v2, see LICENSE
 *
 * Applies known fixes for Spicetify bugs until Spicetify releases them.
 *
 * A fix only applies when the running Spicetify version is in its
 * spicetifyVersions list AND detect() says the bug is present right now.
 * Check what happened in the devtools console with __fixes.status().
 */
(async function spicetifyFixes() {
  "use strict";
  window.__fixes = { version: "1.0.0", status, fixes: [], originals: {} };

  const TAG = "[spicetify-fixes]";
  const WAIT_MS = 30000;
  const POLL_MS = 250;
  const records = window.__fixes.fixes;

  function status() {
    const result = {
      spicetify: window.Spicetify?.Config?.version,
      spotify: window.Spicetify?.Platform?.version,
      fixes: records.map(({ id, state, detail, error }) => ({ id, state, detail, error })),
    };
    console.log(`${TAG} Spicetify ${result.spicetify ?? "?"}, Spotify ${result.spotify ?? "?"}`);
    console.table(result.fixes);
    return result;
  }

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  async function waitFor(check, timeoutMs = WAIT_MS) {
    const end = Date.now() + timeoutMs;
    for (;;) {
      try {
        if (check()) return true;
      } catch {
        // Not ready yet.
      }
      if (Date.now() >= end) return false;
      await sleep(POLL_MS);
    }
  }

  function sourceOf(value) {
    if (typeof value !== "function") return "";
    try {
      return Function.prototype.toString.call(value);
    } catch {
      return "";
    }
  }

  // ---------------------------------------------------------------------------
  // Fix 1: menuitem-v2
  //
  // On Spotify 1.3.4, Spicetify.ReactComponent.MenuItem resolves to Spotify's
  // V2-only menu item, but Spicetify renders its profile-menu items inside the
  // legacy menu. With any Spicetify or extension entry registered, opening the
  // profile menu throws "cannot be rendered outside a collection". Spotify's
  // layout-switching MenuItem (it has both markers below) is the right one.
  // ---------------------------------------------------------------------------

  const MENU_V2_MARK = "forceV2LeadingIcon";
  const MENU_SWITCH_MARK = "aria-describedby";
  let switchingMenuItem = null;
  let profileGuardArmed = false;

  function menuItemSource() {
    const item = window.Spicetify?.ReactComponent?.MenuItem;
    return sourceOf(item) + sourceOf(item?.render);
  }

  function isSwitchingMenuItem(fn) {
    const source = sourceOf(fn);
    return source.includes(MENU_V2_MARK) && source.includes(MENU_SWITCH_MARK);
  }

  // Captures webpack's/rspack's require and returns every exported component
  // that is (or wraps, via forwardRef/memo) the layout-switching MenuItem.
  function findSwitchingMenuItems() {
    const key = Object.keys(window).find((k) => /^(webpack|rspack)Chunk/.test(k));
    if (!key) throw new Error("no webpack/rspack chunk array on window");

    let req;
    window[key].push([[Symbol("spicetify-fixes")], {}, (r) => { req = r; }]);
    if (typeof req !== "function" || !req.m) throw new Error("could not capture the module require function");

    const found = new Set();
    for (const id of Object.keys(req.m)) {
      if (!sourceOf(req.m[id]).includes(MENU_V2_MARK)) continue;

      let exports;
      try {
        exports = req.c?.[id]?.exports ?? req(id);
      } catch {
        continue;
      }

      let candidates;
      try {
        candidates = [exports, ...Object.values(exports ?? {})];
      } catch {
        candidates = [exports];
      }

      for (const value of candidates) {
        if ([value, value?.render, value?.type].some(isSwitchingMenuItem)) found.add(value);
      }
    }
    return [...found];
  }

  // Spicetify's items read MenuItem at render time, so re-checking on
  // pointerdown catches a late reassignment before the menu draws.
  function armProfileMenuGuard() {
    if (profileGuardArmed) return;
    profileGuardArmed = true;
    document.addEventListener(
      "pointerdown",
      (event) => {
        if (event.target instanceof Element && event.target.closest('[data-testid="user-widget-link"]')) {
          reapply("menuitem-v2");
        }
      },
      true,
    );
  }

  // ---------------------------------------------------------------------------
  // Fix 2: topbar-history-class
  //
  // Spicetify waits for .main-globalNav-historyButtons before it mounts Topbar
  // buttons. Spicetify 2.45.3's css-map lacks that class for Spotify 1.3.4, so
  // the wait never ends and no extension or theme button appears.
  //
  // This changes Spotify's DOM for every extension and theme. That's acceptable
  // in a personal fix collection, and it's the reason this stays out of
  // published extensions.
  // ---------------------------------------------------------------------------

  const HISTORY_CLASS = "main-globalNav-historyButtons";
  const HISTORY_WRAPPER = ".main-globalNav-historyButtonsWrapper";
  const HISTORY_BUTTON = `${HISTORY_WRAPPER} [data-encore-id='buttonTertiary']`;
  let historyObserver = null;
  let historyObserved = null;
  let historyFramePending = false;

  function historyButton() {
    return document.querySelector(HISTORY_BUTTON);
  }

  function keepHistoryClass() {
    const button = historyButton();
    if (button?.parentElement && !document.querySelector(`.${HISTORY_CLASS}`)) {
      button.parentElement.classList.add(HISTORY_CLASS);
    }

    // Spotify may rebuild the wrapper; follow it to the new element.
    const target = button?.closest(HISTORY_WRAPPER) ?? document.body;
    if (target !== historyObserved || !historyObserved?.isConnected) {
      historyObserver ??= new MutationObserver(scheduleHistoryCheck);
      historyObserver.disconnect();
      historyObserver.observe(target, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
      historyObserved = target;
    }
  }

  function scheduleHistoryCheck() {
    if (historyFramePending) return;
    historyFramePending = true;
    requestAnimationFrame(() => {
      historyFramePending = false;
      try {
        keepHistoryClass();
      } catch (e) {
        console.warn(TAG, "topbar-history-class: could not keep the class", e);
      }
    });
  }

  // Spicetify's Topbar re-runs its wait on every navigation.
  let historyListening = false;
  function watchHistoryButtons() {
    keepHistoryClass();
    if (historyListening) return;
    historyListening = true;
    try {
      window.Spicetify?.Platform?.History?.listen?.(scheduleHistoryCheck);
    } catch {
      // The observer alone still covers most rebuilds.
    }
  }

  // ---------------------------------------------------------------------------
  // Fix list
  // ---------------------------------------------------------------------------

  const FIXES = [
    {
      id: "menuitem-v2",
      title: "Profile menu won't open",
      symptom:
        'Clicking the profile icon does nothing; the console shows "cannot be rendered outside a collection". ' +
        "Once any Spicetify or extension entry is registered in the profile menu, the whole menu crashes.",
      upstream: [
        "https://github.com/spicetify/cli/pull/4012",
        "https://github.com/spicetify/cli/issues/3965",
        "https://github.com/spicetify/marketplace/issues/1248",
      ],
      // Verified on Spotify 1.3.4.258, 16 Oct 2026.
      spicetifyVersions: ["2.45.3"],
      waitFor: () => Boolean(window.Spicetify?.ReactComponent?.MenuItem),
      detect() {
        const source = menuItemSource();
        return source.includes(MENU_V2_MARK) && !source.includes(MENU_SWITCH_MARK);
      },
      apply() {
        if (!switchingMenuItem) {
          const found = findSwitchingMenuItems();
          if (found.length !== 1) {
            throw new Error(`expected 1 layout-switching MenuItem, found ${found.length}`);
          }
          switchingMenuItem = found[0];
        }
        const components = window.Spicetify.ReactComponent;
        if (!("MenuItem" in window.__fixes.originals)) window.__fixes.originals.MenuItem = components.MenuItem;
        components.MenuItem = switchingMenuItem;
        armProfileMenuGuard();
        return "Spicetify.ReactComponent.MenuItem now uses Spotify's layout-switching MenuItem";
      },
    },
    {
      id: "topbar-history-class",
      title: "Top-bar buttons from extensions and themes never appear (e.g. Hazy's pencil)",
      symptom: "Top-bar buttons registered through Spicetify.Topbar.Button never show up.",
      upstream: ["https://github.com/spicetify/cli/commit/1684023"],
      // Verified on Spotify 1.3.4.258.
      spicetifyVersions: ["2.45.3"],
      waitFor: () => Boolean(historyButton()),
      detect: () => !document.querySelector(`.${HISTORY_CLASS}`) && Boolean(historyButton()),
      apply() {
        historyButton().parentElement.classList.add(HISTORY_CLASS);
        watchHistoryButtons();
        return `added .${HISTORY_CLASS} to the history buttons and keeps it there`;
      },
    },
  ];

  // ---------------------------------------------------------------------------
  // Runner
  // ---------------------------------------------------------------------------

  function setState(record, state, detail = "", error = null) {
    record.state = state;
    record.detail = detail;
    record.error = error;
  }

  function failRecord(record, e) {
    setState(record, "failed", e?.message ?? String(e), String(e?.stack ?? e));
  }

  async function runFix(fix, record) {
    try {
      if (!(await waitFor(fix.waitFor))) {
        setState(record, "skipped", `precondition not met within ${WAIT_MS / 1000} s`);
        return;
      }
      if (!fix.detect()) {
        setState(record, "not-needed", "bug not present");
        return;
      }
      const version = window.Spicetify?.Config?.version;
      if (!fix.spicetifyVersions.includes(version)) {
        setState(
          record,
          "untested-version",
          `bug still present on Spicetify ${version}: verify, then add ${version} to spicetifyVersions`,
        );
        return;
      }
      const detail = fix.apply();
      if (fix.detect()) {
        setState(record, "failed", "bug still present after apply()");
        return;
      }
      setState(record, "applied", detail ?? "");
    } catch (e) {
      failRecord(record, e);
    } finally {
      const line = `${TAG} ${fix.id}: ${record.state}`;
      if (record.state === "failed") console.error(line, record.detail);
      else if (record.state === "applied" || record.state === "not-needed") console.log(line);
      else console.warn(line);
    }
  }

  // Re-applies an applied fix if its bug has come back.
  function reapply(id) {
    const fix = FIXES.find((f) => f.id === id);
    const record = records.find((r) => r.id === id);
    if (!fix || record?.state !== "applied") return;
    try {
      if (!fix.detect()) return;
      fix.apply();
      if (fix.detect()) {
        setState(record, "failed", "bug came back and re-applying didn't remove it");
        console.error(`${TAG} ${id}: failed`, record.detail);
      }
    } catch (e) {
      failRecord(record, e);
      console.error(`${TAG} ${id}: failed`, record.detail);
    }
  }

  try {
    for (const fix of FIXES) {
      records.push({ id: fix.id, title: fix.title, state: "pending", detail: "", error: null });
    }
    await Promise.all(FIXES.map((fix, i) => runFix(fix, records[i])));
  } catch (e) {
    console.error(TAG, "start-up failed", e);
  }
})();
