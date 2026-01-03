import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:path/path.dart';
import 'package:reactive_sqldb/db_helper_manager.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'column_def.dart';
import 'fields.dart';

class ReactiveSqldb {
  Database? _database;
  String name = "mydatabase.db";
  final Map<String, Map<String, ColumnDef>> schema = {}; // store table schemas
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

    final encryptionKey = await DbKeyManager.getKey();

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

    await migrateIfNeeded(path: path, encryptionKey: encryptionKey);

    // Open or create the database
    _database = await openDatabase(
      path,
      password: encryptionKey, // 🔐 SQLCipher magic
      version: 1,
      onCreate: (db, version) async {
        print('🔐 Encrypted database created at $path');
      },
    );

    return _database!;
  }

  /// Fully automatic migration
  Future<void> migrateIfNeeded({
    required String path,
    required String encryptionKey,
  }) async {
    bool alreadyEncrypted = false;

    // Try opening DB with encryption key
    try {
      final testDb = await openDatabase(path, password: encryptionKey);
      await testDb.close();
      alreadyEncrypted = true;
      print('🔐 Encrypted DB detected → migration skipped');
    } catch (_) {
      print('🔁 Plain DB detected → migrating all tables');
    }

    if (alreadyEncrypted) return;

    // Open plain DB
    final plainDb = await openDatabase(path);

    // Create temp encrypted DB
    final tempPath = path + '_encrypted';
    final encryptedDb = await openDatabase(
      tempPath,
      password: encryptionKey,
      version: 1,
    );

    // Attach plain DB inside encrypted DB
    await encryptedDb.execute("ATTACH DATABASE '$path' AS plaintext KEY ''");

    // Get all user tables from plain DB
    final tables = await encryptedDb.rawQuery(
      "SELECT name FROM plaintext.sqlite_master "
      "WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );

    for (final row in tables) {
      final tableName = row['name'] as String;

      // Create table schema in encrypted DB based on schema registry
      final fields = schema[tableName];
      if (fields == null) continue;

      final hasPrimary = fields.values.any((e) => e.type == FieldType.PRIMARY);
      String columns = '';
      fields.forEach((name, def) {
        columns += columns.isEmpty
            ? '$name ${def.toSql()}'
            : ', $name ${def.toSql()}';
      });
      if (!hasPrimary) {
        columns = 'id INTEGER PRIMARY KEY AUTOINCREMENT, $columns';
      }

      await encryptedDb.execute(
        'CREATE TABLE IF NOT EXISTS $tableName ($columns)',
      );

      // Copy data directly inside SQL without loading in Dart
      await encryptedDb.execute(
        'INSERT INTO main.$tableName SELECT * FROM plaintext.$tableName',
      );
    }

    // Detach plain DB
    await encryptedDb.execute('DETACH DATABASE plaintext');
    await encryptedDb.close();
    await plainDb.close();

    // Replace old DB file with encrypted DB
    final encryptedFile = File(tempPath);
    if (File(path).existsSync()) await File(path).delete();
    await encryptedFile.rename(path);

    print('✅ Migration of all tables completed with SQLCipher');
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
          String sql = def.toSql();
          // If PRIMARY key with autoIncrement is false, remove AUTOINCREMENT
          if (def.type == FieldType.PRIMARY && !def.autoIncrement) {
            sql = 'INTEGER PRIMARY KEY';
          }
          columns += columns.isEmpty ? '$name $sql' : ', $name $sql';
        });

        // Add default 'id' primary key only if no primary key exists
        if (!hasPrimary) {
          columns =
              'id INTEGER PRIMARY KEY AUTOINCREMENT ${columns.isNotEmpty ? ', $columns' : ''}';
        }

        // Foreign key support
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
          String sql = def.toSql();
          if (def.type == FieldType.PRIMARY && !def.autoIncrement) {
            sql = 'INTEGER PRIMARY KEY';
          }
          columns += columns.isEmpty ? '$name $sql' : ', $name $sql';
        });

        if (!hasPrimary) {
          columns =
              'id INTEGER PRIMARY KEY AUTOINCREMENT ${columns.isNotEmpty ? ', $columns' : ''}';
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

  /// Returns a map of all user-defined tables with their columns
  /// Example output:
  /// {
  ///   "user": ["id", "name", "email"],
  ///   "orders": ["id", "userId", "amount", "createdAt"]
  /// }
  Future<Map<String, List<String>>> listTablesWithFields() async {
    final db = await getDatabase();
    final result = <String, List<String>>{};

    try {
      // Get all user-defined tables
      final tablesQuery = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );

      for (final tableRow in tablesQuery) {
        final tableName = tableRow['name'] as String;

        // Get columns for this table
        final columnsQuery = await db.rawQuery('PRAGMA table_info($tableName)');
        final columns = columnsQuery.map((c) => c['name'] as String).toList();

        result[tableName] = columns;
      }
    } catch (e, st) {
      print('❌ Failed to list tables with fields: $e');
      print(st);
    }

    return result;
  }
}
