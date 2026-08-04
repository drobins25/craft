# Dial Injection Contract

How a dial physically lives on the user's page: the handles it owns, the four operations that drive it, and the rules that keep measurements honest and teardown total. `dial-inline.md` calls these operations by name; this file is the only place their payloads are defined.

## The three handles

Everything dial injects hangs off exactly three namespaced handles:

1. **`<style id="craft-dial-style">`** - appended to `document.head`. Holds ALL candidate CSS for the session.
2. **`<div id="craft-dial-panel">`** - appended to `document.body` as its **last child**. The fixed control panel.
3. **`document.documentElement.dataset.craftDial`** - the active position, as a lowercase letter (`"a"`, `"b"`, ...). Set on `<html>`, never on any element inside the app.

Any OTHER real node a candidate injects (an approach position's clickable button, badge, or bar - pseudo-elements can't be interactive) MUST carry the attribute **`data-craft-dial-injected`**. The marker is what makes CLEAR total by construction, regardless of injection technique. An unmarked append is a contract violation - it survives teardown and haunts the page.

**React-safe placement rule:** head, body-last-child, and the `<html>` attribute are all outside any framework root, so a re-render cannot strip them. An **in-tree append is forbidden** - React (and every virtual-DOM framework) reconciles only its own root's children, and anything foreign inside that root is subject to removal on the next render. This placement is why the panel survives.

## Candidate CSS shape

Every candidate rule is keyed off the `<html>` attribute, inside the single style element:

```css
html[data-craft-dial="a"] .filter-row { gap: 32px; }
html[data-craft-dial="b"] .filter-row { gap: 24px; }
html[data-craft-dial="c"] .filter-row { gap: 22px; }
```

Toggling a position sets ONE attribute and mutates nothing else. No inline styles on app elements, no class additions, no per-toggle style rewrites - the whole session's candidates coexist in the one stylesheet and the attribute picks the live one.

For **approach** positions that add an element: prefer `::before`/`::after` content under the same `html[data-craft-dial="x"]` key - pseudo-elements are removed with the stylesheet for free. When the candidate needs a real, interactive node (a clickable button), create it with `data-craft-dial-injected` set, so CLEAR's bulk selector removes it. Never an unmarked append.

## The four operations

Each is one `evaluate_script` payload. `dial-inline.md` refers to them by name.

### MEASURE

Read the surface before and during the session. Returns a small JSON-ish object - never a full accessibility tree:

```js
(() => {
  const els = [...document.querySelectorAll('<selector>')]
    .filter(el => el.getClientRects().length > 0 &&
                  getComputedStyle(el).visibility !== 'hidden');
  if (!els.length) return { found: 0 };
  const el = els[0];
  const cs = getComputedStyle(el);
  const r = el.getBoundingClientRect();
  return {
    found: els.length,
    selector: '<selector>',
    value: cs.getPropertyValue('<property>'),
    rect: { x: r.x, y: r.y, w: r.width, h: r.height }
  };
})()
```

**Visibility rule (non-negotiable):** every measured or targeted element must pass `el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden'`. Responsive pages carry BOTH their desktop and mobile faces in the DOM; the hidden face has zero rects and lies about the layout. A bare `querySelector` with no visibility filter is the default mistake - it reports numbers from an element nobody can see.

### INJECT

One payload creates all three handles. Candidate CSS and panel markup are built by the flow; the placement is fixed:

```js
(() => {
  const style = document.createElement('style');
  style.id = 'craft-dial-style';
  style.textContent = `<candidate CSS rules>`;
  document.head.appendChild(style);

  const panel = document.createElement('div');
  panel.id = 'craft-dial-panel';
  panel.innerHTML = `<panel markup>`;
  document.body.appendChild(panel);

  document.documentElement.dataset.craftDial = 'a';
})()
```

Re-injection (a new position mid-session, a refresh recovery) REPLACES the style element's `textContent` and the panel's `innerHTML` through the same ids - it never appends a second style or panel. Positions are never removed once injected; the letter set only grows.

### TOGGLE

```js
document.documentElement.dataset.craftDial = '<letter>';
```

That is the entire operation. The panel's click handlers do the same thing from inside the page; a chat-driven toggle does it via `evaluate_script`.

**Re-measure rule (non-negotiable):** after every toggle, any number reported to the user comes from a fresh MEASURE - a live `getBoundingClientRect()` / `getComputedStyle` read - never from the CSS value that was injected. An injected value that lost a specificity fight, hit a `!important`, or missed its selector reports as "applied" unless it is read back. The readout's whole job is being the receipt that the CSS actually landed.

### CLEAR

The canonical clear, verbatim. This exact snippet - same ids, same order - is what every flow runs; a paraphrase breaks the coverage grep that keeps the call sites aligned:

```js
document.getElementById('craft-dial-style')?.remove();
document.getElementById('craft-dial-panel')?.remove();
document.querySelectorAll('[data-craft-dial-injected]').forEach(el => el.remove());
delete document.documentElement.dataset.craftDial;
```

CLEAR is **idempotent on a page that was never dialed**: optional-chained removal no-ops on absent nodes, the bulk selector matches nothing, and `delete` on an absent dataset key is a silent no-op. Run it unconditionally - before a dial starts (a stale session may have left residue) and on every exit path including abandonment.

## The panel

**Visual register: flat, grey, unmistakably scaffolding.** Dev chrome, never design - anything that looks like design risks being ported as design (the mockup funnel's toggle-bar rule; dial inherits it). No shadows borrowed from the app, no brand colors, no rounded-friendly styling that could read as a real component.

**Isolation:** the host app's reset is unknown and hostile by default. Every panel rule is scoped under `#craft-dial-panel`, and the panel sets its own `font-family` (system stack), `font-size`, `line-height`, `color`, `background`, and `box-sizing` explicitly - an unstyled property inherits the app's. The panel pins `position: fixed` with `z-index: 2147483000`.

**Content per position, strongest handle first:**

- **Letter** - the identity. The only clickable handle. Users say "C, but looser"; nobody says "option gap-xl".
- **Intent word** - `current` / `tighter` / `commit` on a magnitude dial; a one-phrase treatment description on an approach dial.
- **Detail line** - token name plus measured px when the position is on-scale (`gap-md · 24px`); bare measured value when it is not (`22px`). **The absence of a token name IS the off-scale signal. No warning glyph, no "not on your scale" text, no scolding** - a tool whose premise is lightness does not lecture the user about their own taste.

The **active position's letter is bold** - nothing else changes. A mid-conversation glance must tell which position is live without re-reading the panel.

The optional **readout line** (bottom of the panel: `first card at y 493`) appears only when there is something meaningful to measure. The approach shape commonly has nothing to measure - omit the line entirely; an empty readout is noise.

Keep the panel markup to one template string, under ~40 lines, letters as the only interactive elements. Panel clicks set `document.documentElement.dataset.craftDial` and re-bold the active row - no other behavior lives in the page.

## Easy to get wrong

- Measuring the hidden mobile face because the selector matched both faces - the visibility rule exists for this.
- Reporting the injected value instead of re-reading the live one - the re-measure rule exists for this.
- Appending the panel inside the app's root because it "looks better positioned there" - the next re-render eats it.
- A candidate button appended without `data-craft-dial-injected` - CLEAR leaves it behind and a real page ships fake chrome.
- Paraphrasing CLEAR at a call site - the ids are the contract; the coverage test greps for them literally.
