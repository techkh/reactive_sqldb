import 'fields.dart';

class ColumnDef {
  final FieldType type;
  final dynamic defaultValue;
  final bool notNull;
  final bool autoIncrement; // controls PRIMARY AUTOINCREMENT

  const ColumnDef({
    required this.type,
    this.defaultValue,
    this.notNull = false,
    this.autoIncrement = true,
  });

  String toSql({bool forAlter = false}) {
    // PRIMARY key cannot be added via ALTER
    if (forAlter && type == FieldType.PRIMARY) {
      throw Exception('Cannot ALTER TABLE to add PRIMARY KEY');
    }

    String sql = type.sqlType;

    // Only add AUTOINCREMENT for PRIMARY keys if enabled and not ALTER
    if (type == FieldType.PRIMARY && autoIncrement && !forAlter) {
      sql += ' AUTOINCREMENT ';
    }

    // Only add NOT NULL if it's not a PRIMARY key
    if (notNull && !sql.contains('PRIMARY KEY')) {
      sql += ' NOT NULL ';
    }

    // Only add DEFAULT if it's not a PRIMARY key
    if (defaultValue != null && !sql.contains('PRIMARY KEY')) {
      if (defaultValue is String) {
        sql += " DEFAULT '$defaultValue'";
      } else if (defaultValue is bool) {
        sql += ' DEFAULT ${defaultValue ? 1 : 0}';
      } else {
        sql += ' DEFAULT $defaultValue';
      }
    }

    return sql;
  }
}
