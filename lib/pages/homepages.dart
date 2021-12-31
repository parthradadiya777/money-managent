import 'package:flutter/material.dart';
import 'package:moneymanagement/controllers/db_helper.dart';
import 'package:moneymanagement/pages/add.dart';

class Homepage extends StatefulWidget {
  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  Dbhelper dbhelper = Dbhelper();
  int totalbalance = 0;
  int totalexpense = 0;
  int totalincome = 0;

  getTotalincome(Map entireData) {
    totalbalance = 0;
    totalexpense = 0;
    totalincome = 0;
    entireData.forEach((key, value) {
      if (value['type'] == 'Income') {
        totalbalance += (value['amount'] as int);
        totalincome += (value['amount'] as int);
      } else {
        totalbalance -= (value['amount'] as int);
        totalincome += (value['amount'] as int);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0.0,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (context) => Addpage()))
              .whenComplete(() {
            setState(() {});
          });
        },
        child: Icon(
          Icons.add,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      body: FutureBuilder<Map>(
          future: dbhelper.fetch(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text('Unexpected Value'),
              );
            }
            if (snapshot.hasData) {
              if (snapshot.data!.isEmpty) {
                return Center(child: Text('No value Found'));
              }
              getTotalincome(snapshot.data!);
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12.0),
                                color: Colors.white70,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Icon(
                                  Icons.settings,
                                  size: 32.0,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 8.0,
                            ),
                            Text(
                              'Welcome Parth',
                              style: TextStyle(
                                fontSize: 24.0,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12.0),
                            color: Colors.white70,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Icon(
                              Icons.settings,
                              size: 32.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: MediaQuery.of(context).size.width * 0.9,
                    margin: EdgeInsets.all(12.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: const [
                            Colors.blueAccent,
                            Colors.blueGrey,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 20.0,
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Total Balance',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20.0,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(
                            height: 12.0,
                          ),
                          Text(
                            'Rs. $totalbalance',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26.0,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(
                            height: 12.0,
                          ),
                          Padding(
                            padding: EdgeInsets.all(8.0),
                          ),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                cardIncome('$totalincome'.toString()),
                                cardExpness('$totalexpense'.toString()),
                              ])
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text('Recent Expense',
                        style: TextStyle(
                            fontSize: 32,
                            color: Colors.black38,
                            fontWeight: FontWeight.bold)),
                  ),
                  ListView.builder(
                      itemCount: snapshot.data!.length,
                      physics: NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      itemBuilder: (contex, index) {
                        Map dataAtIndex = snapshot.data![index];
                        if (dataAtIndex['type'] == 'Income') {
                          return incomeitle(
                              dataAtIndex['amount'], dataAtIndex['note']);
                        } else {
                          return expenssTile(
                              dataAtIndex['amount'], dataAtIndex['note']);
                        }
                      })
                ],
              );
            } else {
              return Center(child: Text('UnExpected Error!'));
            }
          }),
    );
  }

  Widget cardIncome(String value) {
    return Row(
      children: [
        Container(
          margin: EdgeInsets.only(right: 8.0),
          decoration: BoxDecoration(
            color: Colors.white60,
            borderRadius: BorderRadius.circular(20.0),
          ),
          padding: EdgeInsets.all(6.0),
          child: Icon(
            Icons.arrow_downward,
            size: 20,
            color: Colors.green[700],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Income',
              style: TextStyle(fontSize: 14.0, color: Colors.white30),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 20.0, color: Colors.white30),
            ),
          ],
        )
      ],
    );
  }

  Widget cardExpness(String value) {
    return Row(
      children: [
        Container(
          margin: const EdgeInsets.only(right: 8.0),
          decoration: BoxDecoration(
            color: Colors.white60,
            borderRadius: BorderRadius.circular(20.0),
          ),
          padding: EdgeInsets.all(6.0),
          child: Icon(
            Icons.arrow_upward,
            size: 20,
            color: Colors.red[700],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Expense',
              style: TextStyle(fontSize: 14.0, color: Colors.white30),
            ),
            Text(
              value,
              style: TextStyle(fontSize: 20.0, color: Colors.white30),
            ),
          ],
        )
      ],
    );
  }

  Widget expenssTile(int value, String note) {
    return Container(
      margin: EdgeInsets.all(8.0),
      padding: EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.arrow_circle_up_rounded,
                    size: 20.0,
                    color: Colors.red[700],
                  ),
                  SizedBox(
                    width: 4.0,
                  ),
                  Text(
                    'Expense',
                    style: TextStyle(
                      fontSize: 20.0,
                    ),
                  )
                ],
              ),
            ],
          ),
          Text(
            '- $value',
            style: TextStyle(
              fontSize: 24.0,
              fontWeight: FontWeight.w700,
            ),
          )
        ],
      ),
    );
  }

  Widget incomeitle(int value, String note) {
    return Container(
      margin: EdgeInsets.all(8.0),
      padding: EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.arrow_circle_down_rounded,
                    size: 20.0,
                    color: Colors.red[700],
                  ),
                  SizedBox(
                    width: 4.0,
                  ),
                  Text(
                    'Income',
                    style: TextStyle(
                      fontSize: 20.0,
                    ),
                  )
                ],
              ),
            ],
          ),
          Text(
            '+ $value',
            style: TextStyle(
              fontSize: 24.0,
              fontWeight: FontWeight.w700,
            ),
          )
        ],
      ),
    );
  }
}
