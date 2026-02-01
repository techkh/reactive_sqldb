import 'package:flutter/material.dart';
import 'package:reactive_sqldb/column_def.dart';
import 'dart:async';

import 'package:reactive_sqldb/fields.dart';
import 'package:reactive_sqldb/reactive_sqldb.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _name = 'Unknown';

  var _reactiveSqldbPlugin = ReactiveSqldb(name: "mytesting.db");

  @override
  void initState() {
    super.initState();
    creteTables();
    listTabales();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> creteTables() async {
    // Define your table schema
    //Apply without auto increment

    final userFields = {
      'userId': ColumnDef(
        type: FieldType.PRIMARY,
        primaryKeyName: FieldType.TEXT.sqlType,
        autoIncrement: false, // <-- Primary key without auto-increment
      ),
      'name': ColumnDef(type: FieldType.TEXT, notNull: true),
      'email': ColumnDef(type: FieldType.TEXT),
      'age': ColumnDef(type: FieldType.INTEGER, defaultValue: 18),
    };

    // Create the table
    await _reactiveSqldbPlugin.createTable(
      'testing',
      fields: userFields,
      status: (success, tableName) {
        if (success) {
          print('Table $tableName created successfully!');
        } else {
          print('Failed to create table $tableName');
        }
      },
    );

    // final test2 = {
    //   'userId': ColumnDef(
    //     type: FieldType.PRIMARY,
    //     autoIncrement: true, // <-- Primary key without auto-increment
    //   ),
    //   'name': ColumnDef(type: FieldType.TEXT, notNull: true),
    //   'email': ColumnDef(type: FieldType.TEXT),
    //   'age': ColumnDef(type: FieldType.INTEGER, defaultValue: 18),
    // };

    // Create the table
    // await _reactiveSqldbPlugin.createTable(
    //   'testing2',
    //   fields: test2,
    //   status: (success, tableName) {
    //     if (success) {
    //       print('Table $tableName created successfully!');
    //     } else {
    //       print('Failed to create table $tableName');
    //     }
    //   },
    // );

    ///Create Tables
    // await _reactiveSqldbPlugin.createTable(
    //   "user",
    //   fields: {
    //     "name": ColumnDef(type: FieldType.TEXT, defaultValue: 'asfd'),
    //     "email": ColumnDef(type: FieldType.TEXT, defaultValue: 'sdfasf'),
    //     "gennder": ColumnDef(type: FieldType.TEXT),
    //   },
    //   status: (status, tableName) {},
    // );

    ///Listen Tables
    _reactiveSqldbPlugin.watchTable("testing").listen((rows) {
      print('Rows: $rows');
    });

    ///Insert Data
    await _reactiveSqldbPlugin.insert("testing", {
      "userId": "u124",
      "name": "DarithKuch",
      "email": "david@gmail.com",
      "age": "19",
    });

    ///Update by id Data
    // await _reactiveSqldbPlugin.update("testing", "u123", {
    //   "name": "David 1",
    //   "email": "david1@gmail.com",
    // });

    //Delete by id
    //await _reactiveSqldbPlugin.delete("user", id: 2);

    // await _reactiveSqldbPlugin.updateQuery(
    //   'testing',
    //   {'name': "Updated", "email": "test@mgial.com"},
    //   {'id': 2},
    // );

    //Get All item
    var userAll = await _reactiveSqldbPlugin.getAll(
      "testing",
      {},
      offset: 0,
      limit: 20,
    );
    print(userAll);

    // final rows = await _reactiveSqldbPlugin.getAll('user', {
    //   'deleted_at': ['!=', null],
    // });

    //Query All
    // var userAllQuery = await _reactiveSqldbPlugin.query(
    //   "user",
    //   where: 'name = ? AND email = ?',
    //   args: ["David", 'darith@gmail.com'],
    //   offset: 0,
    //   limit: 10,
    // );

    ///Get one item
    // var user = await _reactiveSqldbPlugin.get("user", {"id": 2});

    // final row = await _reactiveSqldbPlugin.get('user', {
    //   'deleted_at': ['!=', null],
    // });

    ///State Change
    setState(() {
      // _name = user != null ? user["name"].toString() : "";
    });

    //print("User get: $user");
  }

  Future listTabales() async {
    final tablesWithFields = await _reactiveSqldbPlugin
        .listTablesWithFullFieldInfo();

    tablesWithFields.forEach((table, columns) {
      print('Table: $table, Columns: $columns');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app')),
        body: Column(
          children: [
            InkWell(
              onTap: () async {
                await _reactiveSqldbPlugin.dropDatabaseFile();
              },
              child: Text("Drop Database"),
            ),
            InkWell(
              onTap: () async {
                final userFields = {
                  'userId': ColumnDef(
                    type: FieldType.PRIMARY,
                    primaryKeyName: FieldType.TEXT.sqlType,
                    autoIncrement:
                        false, // <-- Primary key without auto-increment
                  ),
                  'name': ColumnDef(type: FieldType.TEXT, notNull: true),
                  'email': ColumnDef(type: FieldType.TEXT),
                  'age': ColumnDef(type: FieldType.INTEGER, defaultValue: 18),
                };

                // Create the table
                await _reactiveSqldbPlugin.createTable(
                  'testing',
                  fields: userFields,
                  status: (success, tableName) {
                    if (success) {
                      print('Table $tableName created successfully!');
                    } else {
                      print('Failed to create table $tableName');
                    }
                  },
                );
              },
              child: Text("Create Database"),
            ),
          ],
        ),
      ),
    );
  }
}
