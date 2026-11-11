# Querying stored location history

Use the existing location service to filter and page stored records:

```dart
// Capture the window once and reuse it for subsequent pages.
final to = DateTime.now();
final from = to.subtract(const Duration(hours: 24));
const pageSize = 50;

Future<List<Location>> readPage(int offset) => Locus.location.query(
  LocationQuery(
    from: from,
    to: to,
    isMoving: true,
    minAccuracy: 20,
    sortOrder: LocationSortOrder.newestFirst,
    limit: pageSize,
    offset: offset,
  ),
);

final firstPage = await readPage(0);
final secondPage = await readPage(pageSize);
```

Android and iOS apply every filter, then the timestamp ordering, then the
offset and limit in native storage. Only the selected page crosses into Dart.
This also applies to `Locus.location.getSummary(query: ...)`.

- Time and rectangular bounds include their edges. Dates represent instants,
  so local and UTC query dates identify the same moment.
- Accuracy values are meters: `minAccuracy: 20` keeps records with accuracy
  **at most** 20 meters; `maxAccuracy: 5` keeps values **at least** 5 meters.
  These retain the existing query field meanings.
- Negative offsets act as zero. A zero or negative limit returns an empty
  list. Omitting a limit requests all matching records and can still produce
  a large response.
- Records with equal timestamps use a deterministic native row tie-breaker.
  Pages are separate reads, so inserts/deletes between requests can change
  an offset-based page.
- Native scans and sorting can still take time. Time ranges and paging stay
  fast, but on iOS an accuracy, motion or bounds filter decodes each stored
  record in the time range, so combine it with `from`/`to` on large
  histories. Queries run away from the platform UI thread; this is not a
  promise of constant-time lookup.
- On iOS, a stored record that cannot be read (corrupt JSON or wrongly typed
  fields) is logged and excluded before paging, so it neither fails the query
  nor shortens a page. iOS queries use their own read-only database
  connection, so a long query does not delay saving new locations.

After updating the SDK, rebuild the Android/iOS host rather than relying on
hot reload. An old native bundle reports `UNSUPPORTED_NATIVE_QUERY`; the SDK
does not fall back to an incorrect page or a full-history Dart read. Database
errors propagate to the caller.

The older `Locus.location.getLocations(limit: ...)` operation keeps its
existing platform behavior. Prefer `query` when ordering or filtering matters.

The history database is encrypted at rest on Android and iOS; see [Data protection](data-protection.md).

## Try it in the example

Open **Demos → Storage → Stored Locations**. Choose the window, order, motion,
page size, accuracy limit, and optional rectangular bounds, then select
**Apply query**. The card validates finite numbers and coordinate ranges,
retains one fixed time window across pages, and resets the page when filters
change. It requests one extra record to enable **Next page** only when another
record exists. Errors offer a retry without showing stale page contents.

The example's **Clear all stored locations** action clears the entire store,
including records outside the query. The query itself only reads records.

See [Testing](../testing/unit-testing.md) for the channel, native SQLite, and
example widget regressions. [Error codes](../reference/error-codes.md#history-query-errors)
describe rebuild, invalid-input, and storage failures.
