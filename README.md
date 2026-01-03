# reactive_sqldb
reactive_sqldb is a powerful SQLite manager that lets you:
- Create dynamic tables at runtime with custom fields.
- Define relational links using foreign keys.
- Perform standard CRUD operations.
- Listen to reactive table updates via Streams — no manual refresh needed.

[![Pub Package](https://img.shields.io/pub/v/reactive_sqldb.svg?style=flat-square)](https://pub.dev/packages/reactive_sqldb)

### deeplink_listener  Key Features : 
1. #### Reactive Queries
- Query data and listen to changes automatically.
- Offline local database support both IOS and Android.
- Advanced create relationship tables.

2. #### CRUD Operations
- Create: Insert single or multiple rows.
- Read: Query rows with filters, sorting, and limits.
- Update: Update rows efficiently with where conditions.
- Delete: Remove rows with conditions.

3. #### SQL Flexibility
- Full SQLite syntax support for advanced queries.
- Use raw queries if needed alongside reactive queries.
- Supports joins, grouping, and aggregations.

## Usage

Make sure to check out [examples](https://github.com/techkh/reactive_sqldb/tree/prod/example)

## Install and Import 
Add the following line to `pubspec.yaml`:
```yaml
    dependencies:
        reactive_sqldb: ^1.0.7
```

```yaml
import 'package:reactive_sqldb/fields.dart';
import 'package:reactive_sqldb/reactive_sqldb.dart';
```

## Using
### Init Datatabase
```yaml
 final _reactiveSqldbPlugin = ReactiveSqldb(name: "mytesting.db");
```

### Watch tables
```yaml
Stream<List<Map<String, dynamic>>> watchTable(String table){}
```
Example:
```yaml
///Listen Tables
_reactiveSqldbPlugin.watchTable("users").listen((rows) {
      print('Rows: $rows');
});
```

### Query with a condition:
1. Function 1
```yaml
Future<Map<String, Object?>?> get(
    String table,
    Map<String, Object?> whereArgs,
  ) 
```
Example:
```yaml
var user = await _reactiveSqldbPlugin.get("user", {
    "email": "david@gmail.com",
});
```
- This fetches one rows or filtered rows based on whereArgs.

2. Function 2
```yaml
 Future<List<Map<String, Object?>>> getAll(
    String table,
    Map<String, Object?>? whereArgs, {
    int? limit,
    int? offset = 0
    })
```
Example:
```yaml
 var userAll = await _reactiveSqldbPlugin.getAll(
      "user",
      {},
      offset: 0,
      limit: 20,
    );
```
- This fetches all or filtered rows based on whereArgs.
- limit : end query (optional)
- offset : start query (optional)

2. Function 3
```yaml
 Future<List<Map<String, dynamic>>> query(
    String table, {
    required String? where,
    required List<dynamic>? args,
    int? limit,
    int? offset = 0,
  }) 
```
Example:
```yaml
var userAllQuery = await _reactiveSqldbPlugin.query(
      "user",
      where: 'name = ? AND email = ?',
      args: ["David", 'darith@gmail.com'],
      offset: 0,
      limit: 10,
);
```
- This fetches all or filtered rows based on args.
- limit : end query (optional)
- offset : start query (optional)

### Insert record 
```yaml
 Future<int> insert(String table, Map<String, dynamic> record) async {}
```
Example:
```yaml
await _reactiveSqldbPlugin.insert("user", {
      "name": "David",
      "email": "david@gmail.com",
      "gennder": "Male",
});
```
### Update record by id
```yaml
 Future<void> update(String table, int id, Map<String, dynamic> record) async { }
```
Example:
```yaml
await _reactiveSqldbPlugin.update("user", 1, {
      "name": "David 1",
      "email": "david1@gmail.com",
});
```
### Delete record by id
```yaml
Future<void> delete(String table, int id) async { }
```
Example:
```yaml

await _reactiveSqldbPlugin.delete("user", 1);

```
### Delete by query 
```yaml
 Future<void> updateQuery(
    String table,
    Map<String, dynamic> record,
    Map<String, dynamic> whereArgs,
  ) async { }
```
Example: 
```
 await _reactiveSqldbPlugin.updateQuery(
      'users',
      {'name': "Updated", "email": "test@mgial.com"},
      {'id': 1},
    );
```

### Raw SQL
Manange query data by your Raw SQL.
1. Query
```yaml
 Future<void> raw(
    String sql, {
    List<Object?>? arguments,
    String? notifyTableName,
  })
```
- Insert 
```yaml
await raw(
  'INSERT INTO users (id, name, email) VALUES (?, ?, ?)',
  arguments: [1, 'Darith', 'darith@gmail.com'],
  notifyTableName: 'users',
);
```
- Update 
```yaml
await raw(
  'UPDATE users SET email = ? WHERE id = ?',
  arguments: ['newemail@gmail.com', 1],
  notifyTableName: 'users',
);

```
- Delete
```yaml
await raw(
  'DELETE FROM users WHERE id = ?',
  arguments: [1],
  notifyTableName: 'users',
);
```
See all other you can check our documents make sure to check out [Documentation](https://pub.dev/documentation/reactive_sqldb/latest/)
Hello everyone 👋

If you want to support me, feel free to do so.  

THANK YOUR SUPPORT ME !!!

============================================

សួស្ដី អ្នកទាំងអស់គ្នា👋 

បើ​អ្នក​ចង់​គាំទ្រ​ខ្ញុំ សូម​ធ្វើ​ដោយ​សេរី , 

សូមអរគុណ

<a  href="https://www.buymeacoffee.com/kdrtech" target="_blank">
<img src="https://cdn.buymeacoffee.com/buttons/default-orange.png" height="41" />
</a>