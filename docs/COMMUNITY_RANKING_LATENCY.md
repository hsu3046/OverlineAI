# Ranking Latency Investigation

Code inspection only; production and upstream latency have not been measured.

## Request Path

- CommunityView's section task calls loadRankings directly, without waiting
  for nearby places, articles, location, or book cover downloads.
- The app sends one GET to api/v1/rankings with kind and category.
- Loans call Data4Library loanItemSrch once for 20 records over the 30 days
  ending yesterday in Korea. Bestsellers call Aladin, a different provider.
- The upstream timeout is 7 seconds, function duration is 10 seconds, and
  the app's request timeout is 12 seconds. These are limits, not measured latency.
- Successful ranking responses advertise shared-cache TTL 6 hours and
  stale-while-revalidate 24 hours. Actual CDN HIT/MISS is not yet verified.

## App-Side Contributors

- Only the last loaded ranking key/list is retained. Returning from another
  kind/category sends another request (network/CDN cache may still help).
- Existing rankings remain visible while a different ranking loads. The
  loading row only appears when the array is empty, so updates can feel stalled.

## Conclusion and Proposed Next Step

No serial fan-out or artificial delay was found. Upstream/cache-miss latency is
plausible, but it is not proven to be the provider's normal speed without timing.
Consider bounded kind/category caches with an explicit freshness policy and
visible loading state on category changes. Keep force refresh behavior intact.
Backend precomputation would be a separate infrastructure decision, not a
necessary first change.

## Implemented Follow-up

- Successful lists (including empty lists) are cached in memory by kind/category
  for 8 hours. Expired entries are pruned on access; the key space is limited
  to the app's ranking kinds and categories. No persistent storage is added.
- Force refresh bypasses the cache, and failed requests do not replace it.
- Category changes clear the previous category's results while fetching; all
  active ranking requests show a loading row, including forced refreshes.
- Cache hits invalidate the previous request ID so late results cannot replace
  the selected cached list or leave loading stuck.
- Tests/CommunityRankings/run.sh uses a URLProtocol stub, not live APIs, to
  cover cache reuse, expiry, force refresh, stale responses, and failure retry.
- First uncached API latency is unchanged; this improves repeat visits and
  makes the waiting state explicit, not the provider's response speed.
