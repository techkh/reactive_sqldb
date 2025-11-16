import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'fields.dart';

class ReactiveSqldb {
  Database? _database;
  String name = "mydatabase.db";
  // Reactive table controllers
  final Map<String, StreamController<List<Map<String, dynamic>>>>
  _tableControllers = {};
  final Map<String, StreamController<void>> _singleTableControllers = {};
  ReactiveSqldb({this.name = "mydatabase.db"});

  /// Initialize database
  Future<Database> getDatabase() async {
    if (_database != null) return _database!;

    // Get platform-safe database path (inside app container)
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, name);

    // Optional: copy prebuilt database from assets if it doesn't exist
    if (!File(path).existsSync()) {
      try {
        final data = await rootBundle.load('assets/$name');
        final bytes = data.buffer.asUint8List();
        await File(path).writeAsBytes(bytes);
        print('Prebuilt database copied to container: $path');
      } catch (e) {
        print('No prebuilt DB found, will create new: $e');
      }
    }

    // Open or create the database
    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        print('Database created at $path');
        // Create initial tables if needed, e.g.:
        // await db.execute('CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)');
      },
    );

    return _database!;
  }

  /// Create table dynamically with fields
  /// fields = {'name': 'TEXT', 'age': 'INTEGER'}
  /// optional foreignKey: 'userId', referenceTable: 'users'
  Future<void> createTable(
    String tableName, {
    required Map<String, FieldType> fields,
    String? foreignKey,
    String? referenceTable,
    Function(bool status, String tableName)? status,
  }) async {
    final db = await getDatabase();
    try {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [tableName],
      );
      final tableExists = tables.isNotEmpty;

      final hasIdField = fields.keys.any((k) => k.toLowerCase() == 'id');

      if (!tableExists) {
        // Table doesn't exist → create
        String columns = hasIdField
            ? ''
            : 'id INTEGER PRIMARY KEY AUTOINCREMENT';
        fields.forEach((name, type) {
          if (name.toLowerCase() == 'id' && !hasIdField) return;
          columns += columns.isEmpty
              ? '$name ${type.sqlType}'
              : ', $name ${type.sqlType}';
        });
        if (foreignKey != null && referenceTable != null) {
          columns +=
              ', FOREIGN KEY($foreignKey) REFERENCES $referenceTable(id) ON DELETE CASCADE';
        }
        await db.execute('CREATE TABLE $tableName($columns)');
        print(
          '✅ Table $tableName created with fields: ${fields.keys.join(', ')}',
        );
        status?.call(true, tableName);
        return;
      }

      // Table exists → check for missing columns
      final existingColumnsQuery = await db.rawQuery(
        'PRAGMA table_info($tableName)',
      );
      final existingMap = {
        for (var c in existingColumnsQuery)
          c['name'] as String: c['type'] as String,
      };

      // Check if table is empty
      final rowCountQuery = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM $tableName',
      );
      final cntValue = rowCountQuery.first['cnt'];
      final isEmptyTable =
          cntValue == null || int.parse(cntValue.toString()) == 0;
      var isFieldNew = false;

      for (var entry in fields.entries) {
        final colName = entry.key;
        final colType = entry.value.sqlType.toUpperCase();

        if (!existingMap.containsKey(colName)) {
          if (isEmptyTable) {
            // Table empty → can recreate if needed
            print('Table is empty, will be recreated later if necessary');
            isFieldNew = true;
          } else {
            // Table has data → add nullable column safely
            String safeType = colType
                .replaceAll('PRIMARY KEY', '')
                .replaceAll('AUTOINCREMENT', '')
                .replaceAll('NOT NULL', '')
                .trim();
            if (!safeType.contains('DEFAULT')) {
              // Add default null explicitly
              safeType += ' DEFAULT NULL';
            }
            await db.execute(
              'ALTER TABLE $tableName ADD COLUMN $colName $safeType',
            );
            print('🆕 Column $colName added safely to $tableName');
          }
        }
      }

      // Optionally, migrate empty table
      if (isFieldNew) {
        print('Table is empty → safe to drop and recreate with all columns');
        String columns = hasIdField
            ? ''
            : 'id INTEGER PRIMARY KEY AUTOINCREMENT';
        fields.forEach((name, type) {
          if (name.toLowerCase() == 'id' && !hasIdField) return;
          columns += columns.isEmpty
              ? '$name ${type.sqlType}'
              : ', $name ${type.sqlType}';
        });
        if (foreignKey != null && referenceTable != null) {
          columns +=
              ', FOREIGN KEY($foreignKey) REFERENCES $referenceTable(id) ON DELETE CASCADE';
        }
        await db.execute('DROP TABLE $tableName');
        await db.execute('CREATE TABLE $tableName($columns)');
        print(
          '✅ Table $tableName recreated with all columns: ${fields.keys.join(', ')}',
        );
      }

      status?.call(true, tableName);
    } catch (e) {
      print('❌ Failed to create/update table $tableName: $e');
      status?.call(false, tableName);
    }

    // Initialize reactive controller
    _singleTableControllers.putIfAbsent(
      tableName,
      () => StreamController<void>.broadcast(),
    );
  }

  /// Stream for reactive updates (void)
  Stream<void> tableStream(String tableName) {
    return _singleTableControllers
        .putIfAbsent(tableName, () => StreamController<void>.broadcast())
        .stream;
  }

  /// Notify table changes
  void notifyTable(String tableName) {
    if (_tableControllers.containsKey(tableName)) {
      _notify(tableName); // pushes rows to watchTable stream
    }

    if (_singleTableControllers.containsKey(tableName)) {
      _singleTableControllers[tableName]!.add(null);
    }
  }

  /// Drop a table and remove its reactive controllers
  Future<void> dropTable(String tableName) async {
    final db = await getDatabase();

    // Drop the table if it exists
    await db.execute('DROP TABLE IF EXISTS $tableName');
    print('🗑 Table $tableName dropped.');

    // Remove reactive controllers
    _singleTableControllers.remove(tableName)?.close();
    _tableControllers.remove(tableName)?.close();
  }

  /// Insert record
  Future<int> insert(String table, Map<String, dynamic> record) async {
    final db = await getDatabase();
    int id = await db.insert(
      table,
      record,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyTable(table);
    return id;
  }

  /// Update record by id
  Future<int> update(String table, int id, Map<String, dynamic> record) async {
    final db = await getDatabase();
    final status = await db.update(
      table,
      record,
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyTable(table);
    return status;
  }

  /// Delete record by id
  // Future<int> delete(String table, int id) async {
  //   final db = await getDatabase();
  //   final status = await db.delete(table, where: 'id = ?', whereArgs: [id]);
  //   notifyTable(table);
  //   return status;
  // }

  /// Delete All and By ID
  Future<int> delete(String table, {int? id}) async {
    final db = await getDatabase();

    int status;

    if (id == null) {
      // delete all rows
      status = await db.delete(table);
    } else {
      // delete specific row
      status = await db.delete(table, where: 'id = ?', whereArgs: [id]);
    }

    notifyTable(table);
    return status;
  }

  Future<int> updateQuery(
    String table,
    Map<String, dynamic> record,
    Map<String, dynamic> whereArgs,
  ) async {
    final db = await getDatabase();

    // Build WHERE clause dynamically (e.g. "id = ? AND email = ?")
    final whereClause = whereArgs.keys.map((k) => '$k = ?').join(' AND ');
    final whereValues = whereArgs.values.toList();

    final status = await db.update(
      table,
      record,
      where: whereClause,
      whereArgs: whereValues,
    );

    notifyTable(table); // optional: trigger UI or cache refresh
    return status;
  }

  /// Get all records
  Future<List<Map<String, Object?>>> getAll(
    String table,
    Map<String, Object?>? whereArgs, {
    int? limit,
    int? offset = 0,
  }) async {
    final db = await getDatabase();

    try {
      if (whereArgs == null || whereArgs.isEmpty) {
        // No filters → return all rows
        return await db.query(table, offset: offset, limit: limit);
      }

      // Build WHERE clause dynamically
      final whereClause = whereArgs.keys.map((k) => '$k = ?').join(' AND ');
      final args = whereArgs.values.toList();

      return await db.query(
        table,
        where: whereClause,
        whereArgs: args,
        offset: offset ?? 0,
        limit: limit,
      );
    } catch (e) {
      print('Database getAll error: $e');
      return [];
    }
  }

  /// Get a single row with dynamic where arguments
  /// Example: get('users', {'id': 1})
  Future<Map<String, Object?>?> get(
    String table,
    Map<String, Object?> whereArgs,
  ) async {
    final db = await getDatabase();

    try {
      if (whereArgs.isEmpty) {
        final rows = await db.query(table, limit: 1);
        return rows.isNotEmpty ? rows.first : null;
      }

      final whereClause = whereArgs.keys.map((k) => '$k = ?').join(' AND ');
      final args = whereArgs.values.toList();

      final rows = await db.query(
        table,
        where: whereClause,
        whereArgs: args,
        limit: 1,
      );

      return rows.isNotEmpty ? rows.first : null;
    } catch (e) {
      print('Database get error: $e');
      return null;
    }
  }

  /// Query with a simple WHERE clause
  Future<List<Map<String, dynamic>>> query(
    String table, {
    required String? where,
    required List<dynamic>? args,
    int? limit,
    int? offset = 0,
  }) async {
    final db = await getDatabase();
    try {
      return await db.query(
        table,
        where: where,
        whereArgs: args,
        offset: offset,
        limit: limit,
      );
    } catch (error) {
      print(error);
      return [];
    }
  }

  /// Watch table for reactive updates (emits rows)
  Stream<List<Map<String, dynamic>>> watchTable(String table) {
    _tableControllers.putIfAbsent(table, () => StreamController.broadcast());
    _notify(table); // initial emit
    return _tableControllers[table]!.stream;
  }

  /// Internal notify listeners
  Future<void> _notify(String table) async {
    if (!_tableControllers.containsKey(table)) return;
    final rows = await getAll(table, {});
    _tableControllers[table]!.add(rows);
  }

  ///Raw
  ///Execute a raw SQL statement
  /// Example: await db.raw('UPDATE users SET name = "John" WHERE id = 1');
  Future<void> raw(
    String sql, {
    List<Object?>? arguments,
    String? notifyTableName,
  }) async {
    final db = await getDatabase();
    await db.execute(sql, arguments);

    // Notify reactive stream for a specific table if provided
    if (notifyTableName != null) {
      notifyTable(notifyTableName);
    }
  }

  /// Query raw SQL and get results
  /// Example: final rows = await db.rawQuery('SELECT * FROM users WHERE age > ?', [20]);
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final db = await getDatabase();
    return await db.rawQuery(sql, arguments);
  }

  /// Execute a raw delete, insert, or update and return affected rows
  /// Example: final count = await db.rawUpdate('DELETE FROM users WHERE id = ?', [1]);
  Future<int> rawUpdate(
    String sql, [
    List<Object?>? arguments,
    String? notifyTableName,
  ]) async {
    final db = await getDatabase();
    final count = await db.rawUpdate(sql, arguments);

    if (notifyTableName != null) {
      notifyTable(notifyTableName);
    }

    return count;
  }
}
