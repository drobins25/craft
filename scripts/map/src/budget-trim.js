'use strict';

// Binary-search the ranked definitions down to the token budget. Includes the
// largest rank-ordered prefix whose rendered slice fits, so the highest-value
// definitions are the ones that survive.

// Rough token estimate. aider samples to estimate; chars/4 is the standard
// approximation and is all the budget gate needs.
function estimateTokens(text) {
  return Math.ceil(text.length / 4);
}

// orderedDefs: definitions in rank order. renderFn(subset) -> slice text.
// Returns the largest rank-ordered prefix whose rendered slice fits the budget.
function trimToBudget(orderedDefs, renderFn, budget) {
  if (estimateTokens(renderFn(orderedDefs)) <= budget) return orderedDefs.slice();
  let lo = 0;
  let hi = orderedDefs.length;
  let best = 0;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    const tokens = estimateTokens(renderFn(orderedDefs.slice(0, mid)));
    if (tokens <= budget) {
      best = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return orderedDefs.slice(0, best);
}

module.exports = { trimToBudget, estimateTokens };
