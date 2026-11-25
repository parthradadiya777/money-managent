import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'cloud_sync.dart';
import 'myntra_label_parser.dart';
import 'meesho_label_parser.dart';

Uint8List? brandLogoBytes;

const bool isTestEnvironment = String.fromEnvironment('APP_ENV') == 'test';
const String hiveBoxName = isTestEnvironment ? 'business_manager_test' : 'business_manager';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { brandLogoBytes = base64Decode(await rootBundle.loadString('assets/digitechified_logo.b64')); } catch (_) {}
  await Hive.initFlutter();
  final dataBox = await Hive.openBox(hiveBoxName);
  if (dataBox.get('Masters') == null) {
    await dataBox.put('Masters', [
      {'Record Type':'Firm','Name':'Demo Fashion Store','GSTIN':'','State':'Gujarat','Platform':'Meesho','Notes':'Initial account mapping'},
      {'Record Type':'Firm','Name':'Demo Home Store','GSTIN':'','State':'Gujarat','Platform':'Meesho','Notes':'Initial account mapping'},
      {'Record Type':'Firm','Name':'Demo Myntra Store','GSTIN':'','State':'Gujarat','Platform':'Myntra','Notes':'Initial account mapping'},
      {'Record Type':'Platform','Name':'Meesho'}, {'Record Type':'Platform','Name':'Myntra'},
      {'Record Type':'Platform','Name':'Flipkart'}, {'Record Type':'Platform','Name':'Amazon'}, {'Record Type':'Platform','Name':'AJIO'},
    ]);
  }
  runApp(const BusinessManagerApp());
}

class BusinessManagerApp extends StatelessWidget {
  const BusinessManagerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Digitechified Business Manager',
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD6A52A), primary: const Color(0xFFD6A52A), secondary: const Color(0xFF111111)), scaffoldBackgroundColor: const Color(0xFFF7F6F2), visualDensity: VisualDensity.standard, cardTheme: const CardThemeData(margin: EdgeInsets.zero), inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), filled: true, fillColor: Colors.white, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13))),
    home: const AuthGate(),
  );
}

const platforms = ['Meesho', 'Myntra', 'Flipkart', 'Amazon', 'AJIO'];
const modules = ['Dashboard','Daily Orders','Returns & RTO','Purchases','Vendor Payments','Settlements','Bank Transactions','Expenses','Masters'];
const Map<String,List<String>> fields = {
 'Daily Orders':['Date','Platform','Firm / Account','Order ID','SKU / Product','Brand','Size','Color','Orders Qty','Gross Order Value','Delivered Qty','Delivered Sales','Commission / Fees','Shipping Fees','Other Deductions','Courier','AWB / Tracking No.','Customer','Pincode','Source PDF','PDF Page'],
 'Returns & RTO':['Date','Platform','Firm / Account','Order ID','SKU / Product','Type','Qty','Refund / Loss Amount','Return Shipping','Reason','Status'],
 'Purchases':['Purchase Date','Firm / GST Entity','Vendor Name','Invoice No.','SKU / Product','Qty','Taxable Value','GST %','GST Amount','Invoice Total','Paid Amount','Balance Due'],
 'Vendor Payments':['Payment Date','Firm / GST Entity','Vendor Name','Purchase Invoice No.','Payment Mode','Reference / UTR','Amount Paid','Notes'],
 'Settlements':['Settlement Date','Platform','Firm / Account','Settlement ID','Period From','Period To','Gross Sales','Refunds / RTO','Fees / Deductions','Net Payable','Bank Received','Difference','Bank Reference'],
 'Bank Transactions':['Date','Bank Account','Firm / GST Entity','Description','Type','Category','Reference / UTR','Credit','Debit'],
 'Expenses':['Date','Firm / GST Entity','Category','Description','Vendor / Paid To','Payment Mode','Amount','GST Amount','Invoice No.'],
 'Masters':['Record Type','Name','GSTIN','State','Platform','Contact','Opening Balance','Notes'],
};


class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 48});
  @override
  Widget build(BuildContext context) => Container(
    width: size * 2.7, height: size,
    decoration: BoxDecoration(color: const Color(0xFF080808), borderRadius: BorderRadius.circular(size * .12)),
    alignment: Alignment.center,
    child: brandLogoBytes == null
      ? Text('D', style: TextStyle(color: const Color(0xFFFFC44F), fontSize: size * .78, fontWeight: FontWeight.w900, height: 1))
      : ClipRRect(borderRadius: BorderRadius.circular(size * .16), child: Image.memory(brandLogoBytes!, width: size * 2.7, height: size, fit: BoxFit.contain)),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final Box box = Hive.box(hiveBoxName);
  @override
  Widget build(BuildContext context) {
    if (!CloudSyncService.configured) return const BusinessHome();
    final token = box.get('cloudToken') as String?;
    if (token == null || token.isEmpty) {
      return LoginPage(onAuthenticated: (value) async {
        await box.put('cloudToken', value);
        if (mounted) setState(() {});
      });
    }
    return const BusinessHome();
  }
}

class LoginPage extends StatefulWidget {
  final Future<void> Function(String token) onAuthenticated;
  const LoginPage({super.key, required this.onAuthenticated});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final business = TextEditingController();
  bool register = false;
  bool busy = false;
  bool obscure = true;
  String? error;

  Future<void> submit() async {
    if (email.text.trim().isEmpty || password.text.isEmpty ||
        (register && business.text.trim().isEmpty)) {
      setState(() => error = 'Please fill all required fields.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final result = await CloudSyncService().authenticate(
        email: email.text.trim(),
        password: password.text,
        businessName: business.text.trim(),
        register: register,
      );
      await widget.onAuthenticated(result['access_token'] as String);
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose(); password.dispose(); business.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Card(
          color: Colors.white,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const BrandMark(size: 62),
              const SizedBox(height: 14),
              const Text('DIGITECHIFIED', textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.4)),
              const SizedBox(height: 4),
              const Text('Business Manager', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              if (register) ...[
                TextField(controller: business, decoration: const InputDecoration(labelText: 'Business / Firm Name')),
                const SizedBox(height: 12),
              ],
              TextField(controller: email, keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 12),
              TextField(controller: password, obscureText: obscure,
                decoration: InputDecoration(labelText: 'Password',
                  helperText: register ? 'Use at least 12 characters' : null,
                  suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => obscure = !obscure)))),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Padding(padding: const EdgeInsets.all(12),
                  child: Text(busy ? 'Please wait...' : register ? 'Create Business Account' : 'Login')),
              ),
              TextButton(
                onPressed: busy ? null : () => setState(() { register = !register; error = null; }),
                child: Text(register ? 'Already registered? Login' : 'New business? Create account'),
              ),
            ]),
          ),
        ),
      ),
    )),
  );
}

class BusinessHome extends StatefulWidget {
 const BusinessHome({super.key});
 @override State<BusinessHome> createState()=>_BusinessHomeState();
}
class _BusinessHomeState extends State<BusinessHome> {
 final Box box=Hive.box(hiveBoxName);
 int selected=0;
 String? _syncMessage;
 String money(num n)=>'₹${n.toStringAsFixed(2)}';
 List<Map> rows(String key){final raw=box.get(key,defaultValue:<dynamic>[]);return (raw as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();}
 num sum(String key,String field)=>rows(key).fold<num>(0,(v,e)=>v+(num.tryParse('${e[field]??0}'.replaceAll(',',''))??0));
 Future<void> saveRows(String key,List<Map> value) async {
  for (final item in value) { item['_syncId'] ??= _newSyncId(); }
  await box.put(key,value);
  await _pushModule(key,value);
 }

 @override
 void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) => _syncOnStart());
 }
 String _newSyncId() => '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
 Future<void> _syncOnStart() async {
  final token = box.get('cloudToken') as String?;
  if (!CloudSyncService.configured || token == null || token.isEmpty) return;
  final api = CloudSyncService(token: token);
  try {
   final remote = await api.fetchRecords();
   for (final module in fields.keys) {
    final local = rows(module);
    final localIds = <String>{};
    for (final item in local) {
     item['_syncId'] ??= _newSyncId();
     localIds.add('${item['_syncId']}');
    }
    for (final item in remote.where((r) => r['module'] == module)) {
     final payload = Map<String, dynamic>.from(item['payload'] as Map);
     final id = '${item['record_id']}';
     payload['_syncId'] ??= id;
     if (!localIds.contains(id)) local.add(payload);
    }
    await box.put(module, local);
   }
   for (final module in fields.keys) {
    final local = rows(module);
    final records = local.map((item) => <String, dynamic>{
     'record_id': '${item['_syncId']}',
     'module': module,
     'payload': item,
    }).toList();
    await api.upsertRecords(records);
   }
   if (mounted) setState(() => _syncMessage = 'Cloud synced');
  } catch (e) {
   if (mounted) setState(() => _syncMessage = 'Sync pending');
   if (mounted) ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Cloud sync issue: ${e.toString().replaceFirst('Exception: ', '')}')));
  }
 }
 Future<void> _pushModule(String module, List<Map> list) async {
  final token = box.get('cloudToken') as String?;
  if (!CloudSyncService.configured || token == null || token.isEmpty) return;
  try {
   final records = list.map((item) => <String, dynamic>{
    'record_id': '${item['_syncId']}',
    'module': module,
    'payload': item,
   }).toList();
   await CloudSyncService(token: token).upsertRecords(records);
   if (mounted) setState(() => _syncMessage = 'Cloud synced');
  } catch (_) {
   if (mounted) setState(() => _syncMessage = 'Sync pending');
  }
 }
 @override Widget build(BuildContext context){
  final wide=MediaQuery.of(context).size.width>850;
  return Scaffold(body:Row(children:[
   if(wide)_sideNav(),
   Expanded(child:Column(children:[_topBar(),Expanded(child:selected==0?_dashboard():_modulePage(modules[selected])),if(!wide)_bottomNav()])),
  ]));
 }
 Widget _sideNav()=>Container(width:235,color:const Color(0xFF101D3A),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
  const Padding(padding:EdgeInsets.fromLTRB(20,28,16,24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   BrandMark(size:46),SizedBox(height:12),
   Text('DIGITECHIFIED',style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold,letterSpacing:1.2)),
   Text('Business Manager',style:TextStyle(color:Color(0xFFB9C7E5),fontSize:12)),
  ])),
  const Divider(color:Color(0xFF33415F)),
  Expanded(child:ListView.builder(itemCount:modules.length,itemBuilder:(c,i){
   final icons=[Icons.dashboard_rounded,Icons.shopping_bag,Icons.assignment_return,Icons.inventory_2,Icons.payments,Icons.account_balance,Icons.account_balance_wallet,Icons.receipt_long,Icons.settings];
   final active=selected==i;
   return ListTile(dense:true,selected:active,selectedTileColor:const Color(0xFF263B67),leading:Icon(icons[i],color:active?Colors.white:const Color(0xFFB9C7E5),size:19),
    title:Text(modules[i],style:TextStyle(color:active?Colors.white:const Color(0xFFB9C7E5),fontSize:13,fontWeight:active?FontWeight.w600:FontWeight.normal)),onTap:()=>setState(()=>selected=i));
  })),
  const Padding(padding:EdgeInsets.all(16),child:Text('Multi Marketplace • Multi GST',style:TextStyle(color:Color(0xFF9EACCA),fontSize:11))),
 ]));
 Widget _topBar()=>Container(height:70,padding:const EdgeInsets.symmetric(horizontal:22),color:Colors.white,child:Row(children:[
  if(MediaQuery.of(context).size.width<=850)const Icon(Icons.menu_rounded,color:Color(0xFF263B67)),
  const SizedBox(width:8),Expanded(child:Text(selected==0?'Business Overview':modules[selected],style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold,color:Color(0xFF17233D)))),
  Chip(avatar:Icon(Icons.circle,size:9,color:_syncMessage=='Cloud synced'?Colors.green:Colors.orange),
   label:Text(_syncMessage ?? (box.get('cloudToken') != null ? 'Cloud sync' : 'Local data'))),
  if (CloudSyncService.configured && box.get('cloudToken') != null)
   IconButton(tooltip:'Sync now', onPressed:_syncOnStart, icon:const Icon(Icons.sync)),
  if (CloudSyncService.configured && box.get('cloudToken') != null)
   IconButton(tooltip:'Logout', onPressed:() async {
    await box.delete('cloudToken');
    if (mounted) Navigator.of(context).pushAndRemoveUntil(
     MaterialPageRoute(builder: (_) => const BusinessManagerApp()), (route) => false);
   }, icon:const Icon(Icons.logout)),
  const SizedBox(width:8),
  const CircleAvatar(backgroundColor:Color(0xFFE9EFFB),child:Text('P',style:TextStyle(color:Color(0xFFD6A52A),fontWeight:FontWeight.bold))),
 ]));
 Widget _bottomNav()=>NavigationBar(
  selectedIndex:selected==0?0:selected==1?1:selected==3?2:selected==6?3:4,
  onDestinationSelected:(i){
   if(i==0){setState(()=>selected=0);}
   else if(i==1){setState(()=>selected=1);}
   else if(i==2){setState(()=>selected=3);}
   else if(i==3){setState(()=>selected=6);}
   else {_showMoreModules();}
  },
  destinations:const[
   NavigationDestination(icon:Icon(Icons.dashboard),label:'Home'),
   NavigationDestination(icon:Icon(Icons.shopping_bag),label:'Orders'),
   NavigationDestination(icon:Icon(Icons.inventory),label:'Purchase'),
   NavigationDestination(icon:Icon(Icons.account_balance),label:'Bank'),
   NavigationDestination(icon:Icon(Icons.more_horiz),label:'More'),
  ],
 );
 Future<void> _showMoreModules()async{
  final options=modules.asMap().entries.where((e)=>e.key!=0&&e.key!=1&&e.key!=3&&e.key!=6).toList();
  final choice=await showModalBottomSheet<int>(context:context,builder:(c)=>SafeArea(child:ListView(shrinkWrap:true,children:[
   const ListTile(title:Text('More sections',style:TextStyle(fontWeight:FontWeight.bold))),
   ...options.map((e)=>ListTile(leading:const Icon(Icons.folder_open),title:Text(e.value),onTap:()=>Navigator.pop(c,e.key))),
  ])));
  if(choice!=null&&mounted)setState(()=>selected=choice);
 }
 Widget _dashboard(){
  final orderQty=sum('Daily Orders','Orders Qty'),sales=sum('Daily Orders','Delivered Sales'),delivered=sum('Daily Orders','Delivered Qty');
  final returnQty=rows('Returns & RTO').where((e)=>'${e['Type']}'.toLowerCase()=='return').fold<num>(0,(v,e)=>v+(num.tryParse('${e['Qty']??0}')??0));
  final rto=rows('Returns & RTO').where((e)=>'${e['Type']}'.toLowerCase()=='rto').fold<num>(0,(v,e)=>v+(num.tryParse('${e['Qty']??0}')??0));
  final received=sum('Settlements','Bank Received'),purchases=sum('Purchases','Invoice Total');
  final bank=(num.tryParse('${box.get('openingBank',defaultValue:0)}')??0)+sum('Bank Transactions','Credit')-sum('Bank Transactions','Debit');
  return ListView(padding:const EdgeInsets.all(22),children:[
   Row(children:[const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('Good business starts with clear numbers.',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold,color:Color(0xFF17233D))),
    SizedBox(height:4),Text('Your marketplace, purchase and cash-flow snapshot.',style:TextStyle(color:Colors.black54)),
   ])),FilledButton.icon(onPressed:_quickAdd,icon:const Icon(Icons.add),label:const Text('Quick Entry'))]),
   const SizedBox(height:20),
   LayoutBuilder(builder:(context,c){
    final count=c.maxWidth>950?4:(c.maxWidth>560?2:1);
    final cards=[
     _metric('Total Orders',orderQty,Icons.shopping_bag_outlined,const Color(0xFFD6A52A),false),
     _metric('Delivered Sales',sales,Icons.trending_up,const Color(0xFF16865B),true),
     _metric('Delivered Qty',delivered,Icons.local_shipping_outlined,const Color(0xFF8A5BD1),false),
     _metric('Bank Balance',bank,Icons.account_balance,const Color(0xFFDA8B25),true),
     _metric('Returns',returnQty,Icons.assignment_return,const Color(0xFFD65A5A),false),
     _metric('RTO',rto,Icons.undo,const Color(0xFFB76A3C),false),
     _metric('Marketplace Received',received,Icons.payments,const Color(0xFF16865B),true),
     _metric('Purchases',purchases,Icons.inventory_2,const Color(0xFF5D6C85),true),
    ];
    return GridView.count(crossAxisCount:count,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),childAspectRatio:count==1?3.4:2.1,crossAxisSpacing:12,mainAxisSpacing:12,children:cards);
   }),
   const SizedBox(height:24),const Text('Marketplace performance',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),const SizedBox(height:10),
   ...platforms.map((p){
    final list=rows('Daily Orders').where((e)=>'${e['Platform']}'.toLowerCase()==p.toLowerCase()).toList();
    final qty=list.fold<num>(0,(v,e)=>v+(num.tryParse('${e['Orders Qty']??0}')??0));
    final value=list.fold<num>(0,(v,e)=>v+(num.tryParse('${e['Delivered Sales']??0}')??0));
    return Card(color:Colors.white,elevation:0,child:ListTile(title:Text(p,style:const TextStyle(fontWeight:FontWeight.w600)),subtitle:Text('$qty orders'),trailing:Text(money(value),style:const TextStyle(fontWeight:FontWeight.bold))));
   }),
   const SizedBox(height:20),const Text('Daily workflow',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),const SizedBox(height:8),
   Wrap(spacing:8,runSpacing:8,children:[
    _action('Add orders',Icons.add_shopping_cart,1),_action('Add purchase',Icons.add_box,3),_action('Record settlement',Icons.payments,5),
    _action('Bank entry',Icons.account_balance,6),_action('Add expense',Icons.receipt_long,7),
   ]),
  ]);
 }
 Widget _metric(String label,num value,IconData icon,Color color,bool currency)=>Card(elevation:0,color:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),side:const BorderSide(color:Color(0xFFE8ECF4))),child:Padding(padding:const EdgeInsets.all(16),child:Row(children:[
  Container(width:42,height:42,decoration:BoxDecoration(color:color.withOpacity(.11),borderRadius:BorderRadius.circular(12)),child:Icon(icon,color:color)),const SizedBox(width:12),
  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[
   Text(label,style:const TextStyle(color:Colors.black54,fontSize:12),maxLines:1,overflow:TextOverflow.ellipsis),const SizedBox(height:5),
   Text(currency?money(value):value.toStringAsFixed(0),style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold,color:Color(0xFF17233D)),maxLines:1,overflow:TextOverflow.ellipsis),
  ]))
 ])));
 Widget _action(String label,IconData icon,int page)=>OutlinedButton.icon(onPressed:()=>setState(()=>selected=page),icon:Icon(icon,size:17),label:Text(label));

 Widget _modulePage(String module){
  final data=rows(module),cols=fields[module]??[];
  return ListView(padding:const EdgeInsets.all(22),children:[
   if (module == 'Daily Orders')
    Container(
     padding: const EdgeInsets.all(20),
     decoration: BoxDecoration(
      gradient: const LinearGradient(
       colors: [Color(0xFF090909), Color(0xFF252525)],
       begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
     ),
     child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
       Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.white.withOpacity(.13), borderRadius: BorderRadius.circular(20)),
        child: const Text('PDF-FIRST WORKFLOW', style: TextStyle(color: Color(0xFFFFC44F), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
       ),
       const SizedBox(height: 10),
       const Text('Daily Marketplace Orders', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
       const SizedBox(height: 5),
       const Text('Upload Myntra or Meesho shipping labels. Orders are saved and shown instantly with date, platform and brand-wise totals.', style: TextStyle(color: Color(0xFFE8E3D5), height: 1.4)),
      ])),
      const SizedBox(width: 12),
      Container(width: 54, height: 54, decoration: BoxDecoration(color: const Color(0xFFFFC44F).withOpacity(.15), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFFFC44F), size: 29)),
     ]),
    )
   else
    Text('${data.length} records',style:const TextStyle(color:Colors.black54)),
   const SizedBox(height:14),
   Wrap(spacing:10,runSpacing:10,children:[
    FilledButton.icon(onPressed:()=>_addRecord(module),icon:const Icon(Icons.add),label:const Text('Add Manually')),
    if(module != 'Daily Orders') ...[
     OutlinedButton.icon(onPressed:()=>_importExcel(module),icon:const Icon(Icons.file_upload_outlined),label:const Text('Import Excel')),
     OutlinedButton.icon(onPressed:()=>_exportExcel(module),icon:const Icon(Icons.file_download_outlined),label:const Text('Export Excel')),
    ],
    if(module=='Daily Orders') FilledButton.icon(onPressed:()=>_importShippingPdf(),icon:const Icon(Icons.picture_as_pdf_outlined),label:const Text('Upload Shipping Label PDF')),
   ]),
   const SizedBox(height:16),if(module=='Daily Orders')_dailyOrderSummary(data),if(module=='Masters')_masterHint(),
   if(data.isEmpty)Container(padding:const EdgeInsets.all(32),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(16)),child:const Column(children:[
    Icon(Icons.inbox_outlined,size:42,color:Colors.black38),SizedBox(height:10),Text('No records yet',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
    SizedBox(height:5),Text('Add a record manually or import an Excel workbook.',style:TextStyle(color:Colors.black54)),
   ])) else Card(color:Colors.white,elevation:0,child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(
    columns:[...cols.take(6).map((c)=>DataColumn(label:Text(c,style:const TextStyle(fontWeight:FontWeight.bold)))),const DataColumn(label:Text('Action'))],
    rows:data.asMap().entries.map((entry){final idx=entry.key,row=entry.value;return DataRow(cells:[
     ...cols.take(6).map((c)=>DataCell(Text('${row[c]??''}',maxLines:1,overflow:TextOverflow.ellipsis))),
     DataCell(Row(mainAxisSize:MainAxisSize.min,children:[
      IconButton(tooltip:'Edit record',icon:const Icon(Icons.edit_outlined,color:Color(0xFF2457C5)),onPressed:()=>_editRecord(module,idx)),
      IconButton(tooltip:'Delete record',icon:const Icon(Icons.delete_outline,color:Colors.red),onPressed:()=>_deleteRecord(module,idx)),
     ])),
    ]);}).toList(),
   ))),

  ]);
 }

 Widget _dailyOrderSummary(List<Map> data) {
  final byPlatform=<String,num>{};
  final byBrand=<String,num>{};
  final byDay=<String,Map<String,num>>{};
  final labels=<String>{};
  for(final row in data) {
   final platform=(row['Platform']??'Unknown').toString().trim();
   final brand=(row['Brand']??'Unassigned').toString().trim();
   final date=(row['Date']??'Not detected').toString().trim();
   final labelId=(row['Label ID']??'').toString().trim();
   if(labelId.isNotEmpty) labels.add(labelId);
   final qty=num.tryParse((row['Orders Qty']??1).toString())??1;
   byPlatform[platform]=(byPlatform[platform]??0)+qty;
   byBrand[brand]=(byBrand[brand]??0)+qty;
   final day=byDay.putIfAbsent(date,()=>{});
   day[platform]=(day[platform]??0)+qty;
  }
  Widget group(String title,Map<String,num> values) => Card(
   color:Colors.white,elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),side:const BorderSide(color:Color(0xFFE8E3D8))),
   child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(title,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:14,color:Color(0xFF171717))),
    const SizedBox(height:10),
    if(values.isEmpty) const Text('No data yet',style:TextStyle(color:Colors.black54)),
    ...values.entries.map((e)=>Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(children:[
      Expanded(child:Text(e.key,style:const TextStyle(color:Color(0xFF4B4B4B)))),
      Text(e.value.toStringAsFixed(0),style:const TextStyle(fontWeight:FontWeight.bold,color:Color(0xFF111111)))
    ]))),
   ])));
  final sortedDays=byDay.keys.toList()..sort((a,b)=>b.compareTo(a));
  return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
   LayoutBuilder(builder:(context,constraints){
    final metrics=Wrap(spacing:10,runSpacing:10,children:[
     _metric('Shipping Labels',labels.length,Icons.local_shipping, const Color(0xFFD6A52A),false),
     _metric('SKU Lines',data.length,Icons.inventory_2, const Color(0xFF333333),false),
    ]);
    return metrics;
   }),
   const SizedBox(height:10),
   LayoutBuilder(builder:(context,constraints){
    final platformCard=group('Platform-wise order quantity',byPlatform);
    final brandCard=group('Brand-wise order quantity',byBrand);
    if(constraints.maxWidth<680)return Column(children:[platformCard,const SizedBox(height:10),brandCard]);
    return Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:platformCard),const SizedBox(width:10),Expanded(child:brandCard)]);
   }),
   const SizedBox(height:14),
   Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:const Color(0xFF111111),borderRadius:BorderRadius.circular(16)),
    child:Row(children:[const Icon(Icons.calendar_month_rounded,color:Color(0xFFFFC84D)),const SizedBox(width:10),const Expanded(child:Text('Day-wise order summary',style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold,fontSize:16))),Text('${sortedDays.length} days',style:const TextStyle(color:Color(0xFFFFC84D),fontWeight:FontWeight.bold))])),
   const SizedBox(height:8),
   if(sortedDays.isEmpty) const Text('No daily orders yet',style:TextStyle(color:Colors.black54)),
   ...sortedDays.map((day){
    final totals=byDay[day]!;
    final total=totals.values.fold<num>(0,(a,b)=>a+b);
    return Card(color:Colors.white,elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14),side:const BorderSide(color:Color(0xFFE8E3D8))),
     child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Expanded(child:Text(day,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:15))),Text('${total.toStringAsFixed(0)} orders',style:const TextStyle(fontWeight:FontWeight.bold,color:Color(0xFF9B7417)))]),
      const Divider(height:16),
      Wrap(spacing:8,runSpacing:8,children:totals.entries.map((e)=>Container(padding:const EdgeInsets.symmetric(horizontal:11,vertical:7),decoration:BoxDecoration(color:const Color(0xFFF7F3E8),borderRadius:BorderRadius.circular(9)),child:Text('${e.key}: ${e.value.toStringAsFixed(0)}',style:const TextStyle(fontWeight:FontWeight.w600,fontSize:12)))).toList())
     ])));
   }),
   const SizedBox(height:10),
   const Text('Only shipping labels are counted. Myntra tax invoices are used only to enrich order details. Multiple SKUs on one label are recorded as separate SKU lines.',style:TextStyle(color:Colors.black54,fontSize:12)),
  ]);
 }

 Widget _masterHint()=>Container(padding:const EdgeInsets.all(12),margin:const EdgeInsets.only(bottom:12),decoration:BoxDecoration(color:const Color(0xFFEAF2FF),borderRadius:BorderRadius.circular(12)),child:const Text('Add firms, GSTINs and vendor details here. Starter examples: Demo Fashion Store, Demo Home Store, Demo Myntra Store and all five marketplaces.',style:TextStyle(color:Color(0xFF24477E))));

 Future<void> _importShippingPdf() async {
  String platform = 'Myntra';
  final selectedPlatform = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Choose marketplace PDF'),
      content: DropdownButtonFormField<String>(
        value: platform,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Marketplace'),
        items: platforms.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
        onChanged: (v) { if (v != null) platform = v; },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, platform), child: const Text('Choose PDF')),
      ],
    ),
  );
  if (selectedPlatform == null) return;
  if (!['Myntra', 'Meesho'].contains(selectedPlatform)) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$selectedPlatform PDF parser is not available yet. Please choose Myntra or Meesho.')));
    return;
  }
  try {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (picked == null) return;
    final bytes = picked.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('The selected PDF is empty or could not be read. Please save the PDF and upload it again.');
    }
    final imported = selectedPlatform == 'Myntra'
        ? MyntraLabelParser.parse(bytes)
        : MeeshoLabelParser.parse(bytes);
    if (imported.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No $selectedPlatform shipping labels found. Check that the correct marketplace PDF was selected.')));
      return;
    }
    final existing = rows('Daily Orders');
    final sourceName = picked.files.single.name;
    for (final item in imported) {
      item['Source PDF'] = sourceName;
      item['Label ID'] = '$sourceName-${item['Label ID']}';
    }
    final knownLabels = existing.map((e) => '${e['Label ID'] ?? ''}').toSet();
    imported.removeWhere((e) => knownLabels.contains('${e['Label ID']}'));
    if (imported.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This PDF has already been imported.')));
      return;
    }
    final labelsCount = imported.map((e) => e['Label ID']).toSet().length;
    final skuCount = imported.length;
    final firms = imported.map((e) => '${e['Firm / Account'] ?? ''}').where((v) => v.trim().isNotEmpty).toSet().toList();
    final brands = imported.map((e) => '${e['Brand'] ?? ''}').where((v) => v.trim().isNotEmpty).toSet().length;
    final ok = mounted ? await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Review PDF import'),
        content: Text('$labelsCount shipping labels found\n$skuCount SKU rows found\n$brands brands detected\n${firms.isEmpty ? 'Seller/Firm not found in PDF' : 'Seller/Firm: ${firms.join(', ')}'}\nTax Invoice pages are used for details only, not counted as orders.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import Orders')),
        ],
      ),
    ) : false;
    if (ok != true) return;
    await saveRows('Daily Orders', [...existing, ...imported]);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$labelsCount labels and $skuCount SKU rows imported successfully.')));
    }
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF import failed: ${e.toString().replaceFirst('Exception: ', '')}')));
  }
 }

 Future<void> _quickAdd()async{
  final choice=await showModalBottomSheet<String>(context:context,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
   const ListTile(title:Text('Quick Entry',style:TextStyle(fontWeight:FontWeight.bold))),
   ...['Daily Orders','Purchases','Returns & RTO','Settlements','Bank Transactions','Expenses'].map((v)=>ListTile(title:Text(v),leading:const Icon(Icons.add_circle_outline),onTap:()=>Navigator.pop(c,v))),
  ])));
  if(choice!=null)_addRecord(choice);
 }
 Future<void> _addRecord(String module)async{
  final controllers=<String,TextEditingController>{};
  for(final f in fields[module]??[])controllers[f]=TextEditingController();
  for(final f in ['Date','Purchase Date','Payment Date','Settlement Date']){if(controllers.containsKey(f))controllers[f]!.text=DateTime.now().toIso8601String().substring(0,10);}
  if(controllers.containsKey('Platform'))controllers['Platform']!.text='Meesho';
  for(final f in ['Firm / Account','Firm / GST Entity']){if(controllers.containsKey(f))controllers[f]!.text='Demo Fashion Store';}
  final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
   title:Text('Add $module'),content:SizedBox(width:520,child:SingleChildScrollView(child:Column(children:controllers.entries.map((e)=>Padding(padding:const EdgeInsets.only(bottom:12),child:_formField(module,e.key,e.value))).toList()))),
   actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save Record'))],
  ));
  if(ok==true){final record=<String,dynamic>{for(final e in controllers.entries)e.key:e.value.text.trim()};if(record.values.every((v)=>'$v'.trim().isEmpty)){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Please enter at least one field.')));}else{final list=rows(module)..add(record);await saveRows(module,list);if(mounted){setState((){});ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Record added successfully.')));}}}
  for(final c in controllers.values){c.dispose();}
 }
 List<String> _optionsFor(String module, String field) {
  final normalized = field.toLowerCase();
  if (normalized == 'platform') {
    final saved = rows('Masters').where((r) => '${r['Record Type']}'.toLowerCase() == 'platform').map((r) => '${r['Name']}'.trim()).where((v) => v.isNotEmpty);
    return {...platforms, ...saved}.toList();
  }
  if (normalized.contains('firm') || normalized.contains('account') || normalized.contains('gst entity')) {
    return rows('Masters').where((r) => '${r['Record Type']}'.toLowerCase() == 'firm').map((r) => '${r['Name']}'.trim()).where((v) => v.isNotEmpty).toSet().toList();
  }
  if (normalized == 'type') return ['Return', 'RTO'];
  if (normalized == 'status') return ['Pending', 'Completed', 'On Hold', 'Cancelled'];
  if (normalized.contains('payment mode')) return ['Bank Transfer', 'UPI', 'Cash', 'Cheque', 'Other'];
  if (normalized == 'record type') return ['Firm', 'Platform', 'Vendor', 'Bank Account', 'Expense Category'];
  if (normalized == 'state') return ['Gujarat', 'Maharashtra', 'Rajasthan', 'Delhi', 'Karnataka', 'Other'];
  if (normalized == 'gst %') return ['0', '5', '12', '18', '28'];
  if (normalized == 'bank account') {
    return rows('Masters').where((r) => '${r['Record Type']}'.toLowerCase() == 'bank account').map((r) => '${r['Name']}'.trim()).where((v) => v.isNotEmpty).toSet().toList();
  }
  return const [];
 }
 Widget _formField(String module, String field, TextEditingController controller) {
  final options = _optionsFor(module, field);
  final dropdown = options.isEmpty ? const SizedBox.shrink() : Padding(
   padding: const EdgeInsets.only(bottom: 7),
   child: DropdownButtonFormField<String>(
    initialValue: options.contains(controller.text) ? controller.text : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: 'Choose $field (optional)', prefixIcon: const Icon(Icons.arrow_drop_down_circle_outlined)),
    hint: const Text('Select or type below'),
    items: options.map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(),
    onChanged: (value) { if (value != null) controller.text = value; },
   ),
  );
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
   dropdown,
   TextField(controller: controller, decoration: InputDecoration(
    labelText: options.isEmpty ? field : 'Or enter $field manually',
    hintText: 'Enter $field',
    prefixIcon: _numeric(field) ? const Icon(Icons.numbers) : null,
   ), keyboardType: _numeric(field) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text),
  ]);
 }
 bool _numeric(String key)=>['Qty','Value','Sales','Fees','Shipping','Deductions','Amount','GST %','Credit','Debit','Balance','Paid','Received'].any((v)=>key.toLowerCase().contains(v.toLowerCase()));
 Future<void> _editRecord(String module,int index) async {
  final list=rows(module);
  if(index<0||index>=list.length)return;
  final original=list[index];
  final controllers=<String,TextEditingController>{
   for(final field in fields[module]??[])
    field:TextEditingController(text:'${original[field]??''}')
  };
  final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
   title:Text('Edit $module'),
   content:SizedBox(width:520,child:SingleChildScrollView(child:Column(
    children:controllers.entries.map((e)=>Padding(
     padding:const EdgeInsets.only(bottom:10),
     child:_formField(module,e.key,e.value),
    )).toList(),
   ))),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
    FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save Changes')),
   ],
  ));
  if(ok==true){
   final updated=<String,dynamic>{
    for(final e in controllers.entries)e.key:e.value.text.trim(),
    if(original['_syncId']!=null)'_syncId':original['_syncId'],
   };
   list[index]=updated;
   await saveRows(module,list);
   if(mounted)setState((){});
  }
  for(final c in controllers.values){c.dispose();}
 }

 Future<void> _deleteRecord(String module,int index) async {
  final list=rows(module);
  final removed=list.removeAt(index);
  final id=removed['_syncId']?.toString();
  await saveRows(module,list);
  final token=box.get('cloudToken') as String?;
  if(id!=null && token!=null && CloudSyncService.configured) {
   try { await CloudSyncService(token:token).deleteRecord(id); } catch (_) {
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(
     const SnackBar(content:Text('Record removed locally; cloud delete will need retry.')));
   }
  }
  if(mounted)setState((){});
 }

 String _normal(String s)=>s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'),'');
 String _canonical(String module,String header){
  final h=_normal(header),cols=fields[module]??[];
  for(final c in cols){if(_normal(c)==h)return c;}
  const aliases={
   'orderqty':'Orders Qty','quantity':'Qty','orderquantity':'Orders Qty','orderdate':'Date','orderid':'Order ID','sku':'SKU / Product',
   'sellingprice':'Gross Order Value','totalamount':'Gross Order Value','grossamount':'Gross Order Value','deliveredamount':'Delivered Sales',
   'deliveredorders':'Delivered Qty','deliveredquantity':'Delivered Qty','platformname':'Platform','selleraccount':'Firm / Account',
   'firm':'Firm / Account','account':'Firm / Account','returntype':'Type','returnreason':'Reason','rtoqty':'Qty',
   'vendor':'Vendor Name','supplier':'Vendor Name','invoicenumber':'Invoice No.','invoicevalue':'Invoice Total',
   'taxableamount':'Taxable Value','gstpercentage':'GST %','gstamount':'GST Amount','paid':'Paid Amount',
   'settlementamount':'Net Payable','netsettlement':'Net Payable','bankreceived':'Bank Received','creditamount':'Credit','debitamount':'Debit'
  };
  return aliases[h]??header;
 }
 Future<void> _importExcel(String module)async{
  try{
   final picked=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['xlsx','xls'],withData:true);
   if(picked==null||picked.files.single.bytes==null)return;
   final excel=Excel.decodeBytes(picked.files.single.bytes!);if(excel.tables.isEmpty)return;
   final sheet=excel.tables[excel.tables.keys.first]!;if(sheet.rows.isEmpty)return;
   final headers=sheet.rows.first.map((c)=>c?.value?.toString()??'').toList();final imported=<Map>[];
   for(final row in sheet.rows.skip(1)){
    final record=<String,dynamic>{};
    for(var i=0;i<headers.length&&i<row.length;i++){if(headers[i].trim().isEmpty)continue;record[_canonical(module,headers[i].trim())]=row[i]?.value?.toString()??'';}
    if(record.values.any((v)=>'$v'.trim().isNotEmpty))imported.add(record);
   }
   final all=rows(module)..addAll(imported);await saveRows(module,all);
   if(mounted){setState((){});ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('${imported.length} rows imported into $module')));}
  }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Import failed: $e')));}
 }
 Future<void> _exportExcel(String module)async{
  try{
   final data=rows(module),cols=fields[module]??[];final book=Excel.createExcel();final sheet=book['Export'];
   sheet.appendRow(cols.map((e)=>TextCellValue(e)).toList());
   for(final row in data){sheet.appendRow(cols.map((e)=>TextCellValue('${row[e]??''}')).toList());}
   final bytes=book.encode();if(bytes==null)return;
   await FilePicker.platform.saveFile(fileName:'${module.replaceAll(' ','_')}.xlsx',bytes:Uint8List.fromList(bytes));
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Excel export ready')));
  }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Export failed: $e')));}
 }
}
