enum FieldType {
  PRIMARY,
  INTEGER,
  REAL,
  TEXT,
  BLOB,
  NUMERIC, // Stores numbers, can be int or real
  BOOLEAN, // Usually stored as INTEGER 0/1
  DATE, // Stored as TEXT (ISO8601) or INTEGER (timestamp)
  DATETIME, // Stored as TEXT (ISO8601) or INTEGER (timestamp)
}

extension FieldTypeExtension on FieldType {
  String get sqlType {
    switch (this) {
      case FieldType.PRIMARY:
        return 'INTEGER PRIMARY KEY AUTOINCREMENT';
      case FieldType.INTEGER:
        return 'INTEGER';
      case FieldType.REAL:
        return 'REAL';
      case FieldType.TEXT:
        return 'TEXT';
      case FieldType.BLOB:
        return 'BLOB';
      case FieldType.NUMERIC:
        return 'NUMERIC';
      case FieldType.BOOLEAN:
        return 'INTEGER'; // SQLite doesn’t have a boolean type
      case FieldType.DATE:
      case FieldType.DATETIME:
        return 'TEXT'; // Store as ISO8601 string
    }
  }
}
