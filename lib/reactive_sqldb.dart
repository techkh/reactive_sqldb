import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'column_def.dart';
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
  /// remove  required Map<String, FieldType> fields,
  Future<void> createTable(
    String tableName, {
    required Map<String, ColumnDef> fields,
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

      final hasPrimary = fields.values.any((e) => e.type == FieldType.PRIMARY);

      // ───────────────────────── CREATE TABLE
      if (!tableExists) {
        String columns = '';

        fields.forEach((name, def) {
          columns += columns.isEmpty
              ? '$name ${def.toSql()}'
              : ', $name ${def.toSql()}';
        });

        if (!hasPrimary) {
          columns = 'id INTEGER PRIMARY KEY AUTOINCREMENT, $columns';
        }

        if (foreignKey != null && referenceTable != null) {
          columns +=
              ', FOREIGN KEY($foreignKey) REFERENCES $referenceTable(id) ON DELETE CASCADE';
        }

        await db.execute('CREATE TABLE $tableName ($columns)');
        status?.call(true, tableName);
        return;
      }

      // ───────────────────────── CHECK EXISTING COLUMNS
      final existing = await db.rawQuery('PRAGMA table_info($tableName)');
      final existingCols = {for (var c in existing) c['name'] as String};

      final rowCount = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM $tableName',
      );
      final isEmpty = int.parse(rowCount.first['cnt'].toString()) == 0;

      bool recreate = false;

      for (var entry in fields.entries) {
        if (!existingCols.contains(entry.key)) {
          if (isEmpty) {
            recreate = true;
          } else {
            await db.execute(
              'ALTER TABLE $tableName ADD COLUMN '
              '${entry.key} ${entry.value.toSql(forAlter: true)}',
            );
          }
        }
      }

      // ───────────────────────── RECREATE IF EMPTY
      if (recreate) {
        String columns = '';

        fields.forEach((name, def) {
          columns += columns.isEmpty
              ? '$name ${def.toSql()}'
              : ', $name ${def.toSql()}';
        });

        if (!hasPrimary) {
          columns = 'id INTEGER PRIMARY KEY AUTOINCREMENT, $columns';
        }

        if (foreignKey != null && referenceTable != null) {
          columns +=
              ', FOREIGN KEY($foreignKey) REFERENCES $referenceTable(id) ON DELETE CASCADE';
        }

        await db.execute('DROP TABLE $tableName');
        await db.execute('CREATE TABLE $tableName ($columns)');
      }

      status?.call(true, tableName);
    } catch (e) {
      print('❌ Failed to create/update table $tableName: $e');
      status?.call(false, tableName);
    }

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
  Future<int> delete(
    String table, {
    int? id,
    Map<String, dynamic>? whereArgs, // value or [operator, value]
  }) async {
    final db = await getDatabase();

    try {
      int status;

      if (id != null) {
        // delete by id
        status = await db.delete(table, where: 'id = ?', whereArgs: [id]);
      } else if (whereArgs != null && whereArgs.isNotEmpty) {
        // build dynamic where clause
        final whereParts = <String>[];
        final args = <Object?>[];

        whereArgs.forEach((key, value) {
          if (value is List && value.length == 2) {
            final op = value[0];
            final val = value[1];
            whereParts.add('$key $op ?');
            args.add(val);
          } else {
            whereParts.add('$key = ?');
            args.add(value);
          }
        });

        final whereClause = whereParts.join(' AND ');

        status = await db.delete(table, where: whereClause, whereArgs: args);
      } else {
        // delete all rows
        status = await db.delete(table);
      }

      // Notify reactive controller
      notifyTable(table);
      return status;
    } catch (e, stack) {
      print('❌ Database delete error on table "$table": $e');
      print(stack);
      return 0;
    }
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
    Map<String, dynamic>?
    whereArgs, { // value can be Object or [operator, value]
    int? limit,
    int? offset = 0,
  }) async {
    final db = await getDatabase();

    try {
      if (whereArgs == null || whereArgs.isEmpty) {
        // No filters → return all rows
        return await db.query(table, offset: offset ?? 0, limit: limit);
      }

      // Build WHERE clause dynamically
      final whereParts = <String>[];
      final args = <Object?>[];

      whereArgs.forEach((key, value) {
        if (value is List && value.length == 2) {
          // e.g., ['!=', 0]
          final op = value[0];
          final val = value[1];
          whereParts.add('$key $op ?');
          args.add(val);
        } else {
          // default '='
          whereParts.add('$key = ?');
          args.add(value);
        }
      });

      final whereClause = whereParts.join(' AND ');

      return await db.query(
        table,
        where: whereClause,
        whereArgs: args,
        offset: offset ?? 0,
        limit: limit,
      );
    } catch (e, stack) {
      print('❌ Database getAll error on table "$table": $e');
      print(stack);
      return [];
    }
  }

  /// Get a single row with dynamic where arguments
  /// Example: get('users', {'id': 1})
  Future<Map<String, Object?>?> get(
    String table,
    Map<String, dynamic> whereArgs, // value can be Object or [operator, value]
  ) async {
    final db = await getDatabase();

    try {
      if (whereArgs.isEmpty) {
        final rows = await db.query(table, limit: 1);
        return rows.isNotEmpty ? rows.first : null;
      }

      // Build WHERE clause dynamically
      final whereParts = <String>[];
      final args = <Object?>[];

      whereArgs.forEach((key, value) {
        if (value is List && value.length == 2) {
          // e.g., ['!=', 0]
          final op = value[0];
          final val = value[1];
          whereParts.add('$key $op ?');
          args.add(val);
        } else {
          // default '='
          whereParts.add('$key = ?');
          args.add(value);
        }
      });

      final whereClause = whereParts.join(' AND ');

      final rows = await db.query(
        table,
        where: whereClause,
        whereArgs: args,
        limit: 1,
      );

      return rows.isNotEmpty ? rows.first : null;
    } catch (e, stack) {
      print('❌ Database get error on table "$table": $e');
      print(stack);
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
