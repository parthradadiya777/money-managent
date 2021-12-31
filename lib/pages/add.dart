// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:moneymanagement/controllers/db_helper.dart';

class Addpage extends StatefulWidget {
  @override
  State<Addpage> createState() => _AddpageState();
}

class _AddpageState extends State<Addpage> {
  int? amount;
  String note = 'Some Expense';
  String type = 'Income';
  DateTime selectedate = DateTime.now();

  List<String> months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  Future<void> _selecteddate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: selectedate,
        firstDate: DateTime(2020, 12),
        lastDate: DateTime.now());
    if (picked != null && picked != selectedate) {
      setState(() {
        selectedate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0.0,
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 20,
          ),
          Text(
            'Add Tansaction',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(
            height: 20,
          ),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.attach_money,
                  size: 24,
                ),
              ),
              SizedBox(
                width: 12,
              ),
              Expanded(
                child: TextField(
                  onChanged: (val) {
                    try {
                      amount = int.parse(val);
                    } catch (e) {}
                  },
                  keyboardType: TextInputType.number,
                  decoration:
                      InputDecoration(hintText: '0', border: InputBorder.none),
                  style: TextStyle(
                    fontSize: 24,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 24,
          ),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.attach_money,
                  size: 24,
                ),
              ),
              SizedBox(
                width: 12,
              ),
              Expanded(
                child: TextField(
                  onChanged: (val) {
                    note = val;
                  },
                  decoration: InputDecoration(
                      hintText: 'Descriptions', border: InputBorder.none),
                  style: TextStyle(
                    fontSize: 24,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 20,
          ),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.money_sharp,
                  size: 24,
                ),
              ),
              SizedBox(
                width: 12,
              ),
              ChoiceChip(
                  onSelected: (v) {
                    if (v) {
                      setState(() {
                        type = 'Income';
                      });
                    }
                  },
                  label: Text(
                    'Income',
                    style: TextStyle(
                        color: type == 'Income' ? Colors.white : Colors.black),
                  ),
                  selected: type == 'Income' ? true : false),
              SizedBox(
                width: 12,
              ),
              ChoiceChip(
                  onSelected: (v) {
                    if (v) {
                      setState(() {
                        type = 'Expense';
                      });
                    }
                  },
                  label: Text(
                    'Expense',
                    style: TextStyle(
                        color: type == 'Expense' ? Colors.white : Colors.black),
                  ),
                  selected: type == 'Expense' ? true : false),
            ],
          ),
          SizedBox(
            height: 24,
          ),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.date_range,
                  size: 24,
                ),
              ),
              SizedBox(
                height: 50,
                child: TextButton(
                  onPressed: () {
                    _selecteddate(context);
                  },
                  child: Text(
                    '${selectedate.day} ${months[selectedate.month - 1]}',
                    style: TextStyle(fontSize: 24),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 24,
          ),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: () async {
                if (amount != null && note.isNotEmpty) {
                  Dbhelper dbhelper = Dbhelper();

                  await dbhelper.addData(amount!, selectedate, note, type);
                  Navigator.pop(context);
                } else {
                  print('Not all Value Provider');
                }
              },
              child: Text(
                'Add',
                style: TextStyle(fontSize: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
