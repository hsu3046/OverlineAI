# Reading Record Bookmark

- Add/edit reading records show a bookmark icon and the label 책갈피, without
  explanatory copy. The optional number field is hidden for completed records.
- Hidden values are preserved when completing a record, and restored when
  switching back to reading, paused, or abandoned.
- ReadingRecord.bookmarkPage is an optional positive integer. Empty/zero values
  are stored as nil; existing serialized records decode with nil automatically.
- The field is part of the existing Codable record, so it travels with library
  persistence and backup data. No separate preferences or storage are added.
- Tests cover serialization, legacy decoding, completion preservation, clearing,
  and invalid values in Tests/LibraryContentRevision.
