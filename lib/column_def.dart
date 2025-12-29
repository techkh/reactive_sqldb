import 'fields.dart';

class ColumnDef {
  final FieldType type;
  final dynamic defaultValue;
  final bool notNull;

  const ColumnDef({
    required this.type,
    this.defaultValue,
    this.notNull = false,
  });

  String toSql({bool forAlter = false}) {
    // PRIMARY key must NOT be added via ALTER
    if (forAlter && type == FieldType.PRIMARY) {
      throw Exception('Cannot ALTER TABLE to add PRIMARY KEY');
    }

    String sql = type.sqlType;

    if (notNull && !sql.contains('PRIMARY KEY')) {
      sql += ' NOT NULL';
    }

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
