import 'package:flutter/material.dart';
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

  final _reactiveSqldbPlugin = ReactiveSqldb(name: "mytesting.db");

  @override
  void initState() {
    super.initState();
    creteTables();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> creteTables() async {
    ///Create Tables
    await _reactiveSqldbPlugin.createTable(
      "user",
      fields: {
        "name": FieldType.TEXT,
        "email": FieldType.TEXT,
        "gennder": FieldType.TEXT,
      },
      status: (status, tableName) {},
    );

    ///Listen Tables
    _reactiveSqldbPlugin.watchTable("users").listen((rows) {
      print('Rows: $rows');
    });

    ///Insert Data
    await _reactiveSqldbPlugin.insert("user", {
      "name": "David",
      "email": "david@gmail.com",
      "gennder": "Male",
    });

    ///Update by id Data
    await _reactiveSqldbPlugin.update("user", 1, {
      "name": "David 1",
      "email": "david1@gmail.com",
    });

    //Delete by id
    await _reactiveSqldbPlugin.delete("user", 1);

    ///Get one item
    var user = await _reactiveSqldbPlugin.get("user", {
      "email": "david@gmail.com",
    });

    await _reactiveSqldbPlugin.updateQuery(
      'users',
      {'name': "Updated", "email": "test@mgial.com"},
      {'id': 1},
    );

    //Get All item
    var userAll = await _reactiveSqldbPlugin.getAll(
      "user",
      {},
      offset: 0,
      limit: 20,
    );
    //Query All
    var userAllQuery = await _reactiveSqldbPlugin.query(
      "user",
      where: 'name = ? AND email = ?',
      args: ["David", 'darith@gmail.com'],
      offset: 0,
      limit: 10,
    );

    ///State Change
    setState(() {
      _name = user != null ? user["name"].toString() : "";
    });

    print("User get: $user");
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app')),
        body: Center(child: Text('Running on: $_name\n')),
      ),
    );
  }
}
