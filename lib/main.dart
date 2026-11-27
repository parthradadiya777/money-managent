import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:syncfusion_flutter_pdf/pdf.dart';
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
String activeHiveBoxName = hiveBoxName;

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
const modules = ['Dashboard','Daily Orders','Returns & RTO','Vendor Payments','Bank Received','Expenses','Financial Reports','Vendor Payment Transactions','Opening Balances'];
const Map<String,List<String>> fields = {
 'Daily Orders':['Date','Platform','Firm / Account','Order ID','SKU / Product','Brand','Size','Color','Orders Qty','Gross Order Value','Delivered Qty','Delivered Sales','Commission / Fees','Shipping Fees','Other Deductions','Courier','AWB / Tracking No.','Customer','Pincode','Source PDF','PDF Page'],
 'Returns & RTO':['Date','Platform','RTO / Return','Details'],
 'Vendor Payments':['Month','Firm Name','Vendor Name','Opening Balance','New Amount','Closing Balance','Amount Paid','Payment Date','Payment Mode','Notes'],
 'Bank Received':['Date','Platform','Amount','Details','Brand'],
 'Expenses':['Date','Expense','Details','Payment Mode'],
 'Vendor Payment Transactions':['Date','Firm Name','Vendor Name','Amount','Payment Mode','Notes'],
 'Opening Balances':['Date','Account Type','Account Name','Opening Balance','Notes'],
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
  final Box authBox = Hive.box(hiveBoxName);
  bool loading = true;
  String? role;
  String? error;
  @override
  void initState() { super.initState(); _restoreSession(); }
  Future<void> _restoreSession() async {
    final token = authBox.get('cloudToken') as String?;
    if (!CloudSyncService.configured) {
      activeHiveBoxName = hiveBoxName;
      if (mounted) setState(() { loading = false; role = 'local'; });
      return;
    }
    if (token == null || token.isEmpty) {
      activeHiveBoxName = hiveBoxName;
      if (mounted) setState(() { loading = false; role = null; });
      return;
    }
    try {
      if (authBox.get('cloudImpersonating') == true) {
        final tenantId = '${authBox.get('cloudTenantId') ?? ''}';
        if (tenantId.isEmpty) throw Exception('Partner session is missing its workspace.');
        await _openPartnerBox(tenantId, token);
        if (mounted) setState(() { loading = false; role = 'impersonating'; error = null; });
        return;
      }
      final me = await CloudSyncService(token: token).fetchMe();
      final accountRole = '${me['role'] ?? 'partner'}';
      if (accountRole == 'super_admin') {
        activeHiveBoxName = hiveBoxName;
      } else {
        await _openPartnerBox('${me['tenant_id']}', token);
      }
      if (mounted) setState(() { loading = false; role = accountRole; error = null; });
    } catch (e) {
      if (mounted) setState(() { loading = false; error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }
  Future<void> _openPartnerBox(String tenantId, String token) async {
    activeHiveBoxName = '${hiveBoxName}_$tenantId';
    final partnerBox = await Hive.openBox(activeHiveBoxName);
    await partnerBox.put('cloudToken', token);
    await partnerBox.put('cloudTenantId', tenantId);
    if (!partnerBox.containsKey('Masters')) {
      await partnerBox.put('Masters', [
        {'Record Type':'Platform','Name':'Meesho'},
        {'Record Type':'Platform','Name':'Myntra'},
        {'Record Type':'Platform','Name':'Flipkart'},
        {'Record Type':'Platform','Name':'Amazon'},
        {'Record Type':'Platform','Name':'AJIO'},
      ]);
    }
  }
  Future<void> _onAuthenticated(String token, String accountRole) async {
    await authBox.put('cloudToken', token);
    await authBox.put('cloudRole', accountRole);
    await authBox.delete('cloudImpersonating');
    if (accountRole == 'super_admin') {
      activeHiveBoxName = hiveBoxName;
    } else {
      final me = await CloudSyncService(token: token).fetchMe();
      await _openPartnerBox('${me['tenant_id']}', token);
    }
    if (mounted) setState(() { role = accountRole; loading = false; error = null; });
  }
  @override
  Widget build(BuildContext context) {
    if (!CloudSyncService.configured) return const BusinessHome();
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (error != null) return Scaffold(body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const BrandMark(size: 54), const SizedBox(height: 16),
        Text(error!, textAlign: TextAlign.center), const SizedBox(height: 12),
        FilledButton(onPressed: () { setState(() { loading = true; error = null; }); _restoreSession(); }, child: const Text('Retry')),
        TextButton(onPressed: () async {
          await authBox.delete('cloudToken');
          await authBox.delete('cloudAdminToken');
          await authBox.delete('cloudImpersonating');
          if (mounted) setState(() { role = null; error = null; });
        }, child: const Text('Sign in again')),
      ]),
    )));
    if (role == null) return LoginPage(onAuthenticated: _onAuthenticated);
    if (role == 'super_admin') return const AdminHome();
    return const BusinessHome();
  }
}

class LoginPage extends StatefulWidget {
  final Future<void> Function(String token, String role) onAuthenticated;
  const LoginPage({super.key, required this.onAuthenticated});
  @override
  State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool obscure = true;
  String? error;
  Future<void> submit() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Please enter your Login ID and password.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final result = await CloudSyncService().authenticate(
        email: email.text.trim(), password: password.text, register: false,
      );
      await widget.onAuthenticated(result['access_token'] as String, '${result['role'] ?? 'partner'}');
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Card(color: Colors.white, elevation: 1, child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const BrandMark(size: 62), const SizedBox(height: 14),
            const Text('DIGITECHIFIED', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.4)),
            const SizedBox(height: 4),
            const Text('Business Manager', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Login ID')),
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: obscure, decoration: InputDecoration(labelText: 'Password',
              suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => obscure = !obscure)))),
            if (error != null) ...[const SizedBox(height: 12), Text(error!, style: const TextStyle(color: Colors.red))],
            const SizedBox(height: 18),
            FilledButton(onPressed: busy ? null : submit, child: Padding(padding: const EdgeInsets.all(12), child: Text(busy ? 'Please wait...' : 'Secure Login'))),
            const SizedBox(height: 8),
            const Text('Partner accounts are created by Digitechified Admin.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        )),
      ),
    )),
  );
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  final Box authBox = Hive.box(hiveBoxName);
  List<Map<String, dynamic>> partners = [];
  bool loading = true;
  String? error;
  CloudSyncService get api => CloudSyncService(token: authBox.get('cloudToken') as String?);

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    setState(() { loading = true; error = null; });
    try { partners = await api.listPartners(); }
    catch (e) { error = e.toString().replaceFirst('Exception: ', ''); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> _createPartner() async {
    final name = TextEditingController();
    final login = TextEditingController();
    final password = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Create Partner Account'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Partner / Business Name')),
        const SizedBox(height: 10),
        TextField(controller: login, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Login ID (email)')),
        const SizedBox(height: 10),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Initial Password (minimum 12 characters)')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create Partner')),
      ],
    ));
    if (ok == true) {
      try {
        await api.createPartner(name: name.text.trim(), loginId: login.text.trim(), password: password.text);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Partner account created.')));
        await _refresh();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
    name.dispose(); login.dispose(); password.dispose();
  }

  Future<void> _editPartner(Map<String, dynamic> p) async {
    final name = TextEditingController(text: '${p['name'] ?? ''}');
    final login = TextEditingController(text: '${p['login_id'] ?? ''}');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Edit Partner'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Partner Name')),
        const SizedBox(height: 10),
        TextField(controller: login, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Login ID')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save Changes')),
      ],
    ));
    if (ok == true) {
      try { await api.updatePartner('${p['tenant_id']}', {'name': name.text.trim(), 'login_id': login.text.trim()}); await _refresh(); }
      catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
    }
    name.dispose(); login.dispose();
  }

  Future<void> _togglePartner(Map<String, dynamic> p) async {
    final status = p['status'] == 'active' ? 'disabled' : 'active';
    try { await api.updatePartner('${p['tenant_id']}', {'status': status}); await _refresh(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
  }

  Future<void> _resetPassword(Map<String, dynamic> p) async {
    final password = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Reset password • ${p['name']}'),
      content: TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'New password (minimum 12 characters)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset Password')),
      ],
    ));
    if (ok == true) {
      try {
        await api.resetPartnerPassword('${p['tenant_id']}', password.text);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
    password.dispose();
  }

  Future<void> _openPartner(Map<String, dynamic> p) async {
    try {
      final result = await api.accessPartner('${p['tenant_id']}');
      final token = result['access_token'] as String;
      final tenantId = result['tenant_id'] as String;
      await authBox.put('cloudAdminToken', authBox.get('cloudToken'));
      await authBox.put('cloudToken', token);
      await authBox.put('cloudImpersonating', true);
      await authBox.put('cloudTenantId', tenantId);
      await authBox.put('cloudAdminPartnerName', result['partner_name']);
      await authBox.put('cloudRole', 'super_admin');
      activeHiveBoxName = '${hiveBoxName}_$tenantId';
      final partnerBox = await Hive.openBox(activeHiveBoxName);
      await partnerBox.put('cloudToken', token);
      await partnerBox.put('cloudTenantId', tenantId);
      if (!partnerBox.containsKey('Masters')) {
        await partnerBox.put('Masters', [
          {'Record Type':'Platform','Name':'Meesho'},
          {'Record Type':'Platform','Name':'Myntra'},
          {'Record Type':'Platform','Name':'Flipkart'},
          {'Record Type':'Platform','Name':'Amazon'},
          {'Record Type':'Platform','Name':'AJIO'},
        ]);
      }
      if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const BusinessHome()), (route) => false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _logout() async {
    for (final key in ['cloudToken','cloudAdminToken','cloudImpersonating','cloudTenantId','cloudAdminPartnerName','cloudRole']) {
      await authBox.delete(key);
    }
    activeHiveBoxName = hiveBoxName;
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const BusinessManagerApp()), (route) => false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F6F2),
    appBar: AppBar(
      backgroundColor: const Color(0xFF080808),
      foregroundColor: Colors.white,
      title: const Row(children: [BrandMark(size: 34), SizedBox(width: 12), Text('DIGITECHIFIED • SUPER ADMIN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))]),
      actions: [
        IconButton(tooltip: 'Refresh partners', onPressed: _refresh, icon: const Icon(Icons.refresh)),
        IconButton(tooltip: 'Logout', onPressed: _logout, icon: const Icon(Icons.logout)),
      ],
    ),
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Partner Management', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF17233D))),
            Text('Create and control independent partner workspaces', style: TextStyle(color: Colors.black54, fontSize: 12)),
          ])),
          FilledButton.icon(onPressed: _createPartner, icon: const Icon(Icons.add), label: const Text('Add Partner')),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: _metric('Total Partners', partners.length.toString(), Icons.groups_2)),
          const SizedBox(width: 10),
          Expanded(child: _metric('Active', partners.where((p) => p['status'] == 'active').length.toString(), Icons.verified_user)),
          const SizedBox(width: 10),
          Expanded(child: _metric('Disabled', partners.where((p) => p['status'] != 'active').length.toString(), Icons.block)),
        ]),
        const SizedBox(height: 18),
        if (loading) const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (error != null) Expanded(child: Center(child: Text(error!, textAlign: TextAlign.center)))
        else if (partners.isEmpty) const Expanded(child: Center(child: Text('No partners created yet. Add the first partner.')))
        else Expanded(child: ListView.separated(
          itemCount: partners.length,
          separatorBuilder: (_, __) => const SizedBox(height: 9),
          itemBuilder: (ctx, i) {
            final p = partners[i];
            final active = p['status'] == 'active';
            final title = '${p['name'] ?? 'Partner'}';
            return Card(
              color: Colors.white, elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE8E3D9))),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                leading: CircleAvatar(backgroundColor: const Color(0xFFFFF4D8), child: Text(title.isNotEmpty ? title[0].toUpperCase() : 'P', style: const TextStyle(color: Color(0xFF9A7116), fontWeight: FontWeight.bold))),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${p['login_id']}  •  ${p['partner_code']}\n${active ? 'Active' : 'Disabled'}', style: const TextStyle(height: 1.5)),
                isThreeLine: true,
                trailing: Wrap(alignment: WrapAlignment.end, children: [
                  if (active) IconButton(tooltip: 'Open partner workspace', onPressed: () => _openPartner(p), icon: const Icon(Icons.login, color: Color(0xFFB88919))),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _editPartner(p);
                      if (v == 'status') _togglePartner(p);
                      if (v == 'password') _resetPassword(p);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit partner')),
                      PopupMenuItem(value: 'status', child: Text(active ? 'Disable partner' : 'Activate partner')),
                      const PopupMenuItem(value: 'password', child: Text('Reset password')),
                    ],
                  ),
                ]),
              ),
            );
          },
        )),
        const SizedBox(height: 8),
        const Text('Partner staff accounts are disabled. Only Digitechified Admin can create and manage partner logins.', style: TextStyle(fontSize: 11, color: Colors.black54)),
      ])),
    )),
  );

  Widget _metric(String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFE8E3D9))),
    child: Row(children: [
      Icon(icon, color: const Color(0xFFB88919)), const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      ])),
    ]),
  );
}

class BusinessHome extends StatefulWidget {
 const BusinessHome({super.key});
 @override State<BusinessHome> createState()=>_BusinessHomeState();
}
class _BusinessHomeState extends State<BusinessHome> {
 final Box box=Hive.box(activeHiveBoxName);
 final TextEditingController _dailySearchController=TextEditingController();
 int _dailyPage=0;
 static const int _dailyPageSize=100;
 bool _pdfImporting=false;
 int selected=0;
 int selectedFyStart=DateTime.now().month>=4?DateTime.now().year:DateTime.now().year-1;
 int selectedMonth=DateTime.now().month;
 String? _syncMessage;
 String money(num n)=>'₹${n.toStringAsFixed(2)}';
 List<Map> rows(String key){final raw=box.get(key,defaultValue:<dynamic>[]);final result=(raw as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();if(key=='Daily Orders'){for(final row in result){if('${row['Platform']??''}'.toLowerCase()=='myntra'){row['Brand']='JIPROSTORE';for(final field in ['Date','Firm / Account','Order ID']){if('${row[field]??''}'.trim().isEmpty)row[field]=field=='Date'?'Not detected':field=='Order ID'?(row['AWB / Tracking No.']??'Not detected'):'Not detected';}}}}return result;}
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
 Future<void> _returnToAdmin() async {
  final authBox = Hive.box(hiveBoxName);
  final adminToken = authBox.get('cloudAdminToken') as String?;
  if (adminToken == null || adminToken.isEmpty) return;
  await authBox.put('cloudToken', adminToken);
  await authBox.delete('cloudAdminToken');
  await authBox.delete('cloudImpersonating');
  await authBox.delete('cloudTenantId');
  await authBox.delete('cloudAdminPartnerName');
  await box.delete('cloudToken');
  activeHiveBoxName = hiveBoxName;
  if (mounted) Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AdminHome()), (route) => false);
 }
 Future<void> _logout() async {
  final authBox = Hive.box(hiveBoxName);
  for (final key in ['cloudToken','cloudAdminToken','cloudImpersonating','cloudTenantId','cloudAdminPartnerName','cloudRole']) {
   await authBox.delete(key);
  }
  await box.delete('cloudToken');
  activeHiveBoxName = hiveBoxName;
  if (mounted) Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const BusinessManagerApp()), (route) => false);
 }
 @override Widget build(BuildContext context){
  final wide=MediaQuery.of(context).size.width>850;
  return Scaffold(body:Row(children:[
   if(wide)_sideNav(),
   Expanded(child:Column(children:[_topBar(),_periodFilterBar(),Expanded(child:selected==0?_dashboard():selected==6?_financialReportsPage():_modulePage(modules[selected])),if(!wide)_bottomNav()])),
  ]));
 }
 Widget _sideNav()=>Container(width:235,color:const Color(0xFF080808),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
  const Padding(padding:EdgeInsets.fromLTRB(20,28,16,24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   BrandMark(size:46),SizedBox(height:12),
   Text('DIGITECHIFIED',style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold,letterSpacing:1.2)),
   Text('Business Manager',style:TextStyle(color:Color(0xFFB9B9B9),fontSize:12)),
  ])),
  const Divider(color:Color(0xFF333333)),
  Expanded(child:ListView.builder(itemCount:8,itemBuilder:(c,index){
   const visibleModules=[0,1,2,4,5,6,7,8];
   final i=visibleModules[index];
   final icons=[Icons.dashboard_rounded,Icons.shopping_bag,Icons.assignment_return,Icons.payments,Icons.account_balance,Icons.receipt_long,Icons.assessment,Icons.payment,Icons.account_balance_wallet];
   final active=selected==i;
   return ListTile(dense:true,selected:active,selectedTileColor:const Color(0xFF292313),leading:Icon(icons[i],color:active?const Color(0xFFFFC84D):const Color(0xFFB9B9B9),size:19),
    title:Text(_moduleTitle(modules[i]),style:TextStyle(color:active?Colors.white:const Color(0xFFB9C7E5),fontSize:13,fontWeight:active?FontWeight.w600:FontWeight.normal)),onTap:()=>setState(()=>selected=i));
  })),
  const Padding(padding:EdgeInsets.all(16),child:Text('Multi Marketplace • Multi GST',style:TextStyle(color:Color(0xFF999999),fontSize:11))),
 ]));
 Widget _topBar()=>Container(height:70,padding:const EdgeInsets.symmetric(horizontal:22),color:Colors.white,child:Row(children:[
  if(MediaQuery.of(context).size.width<=850)const Icon(Icons.menu_rounded,color:Color(0xFF263B67)),
  const SizedBox(width:8),Expanded(child:Text(selected==0?'Business Overview':_moduleTitle(modules[selected]),style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold,color:Color(0xFF17233D)))),
  Chip(avatar:Icon(Icons.circle,size:9,color:_syncMessage=='Cloud synced'?Colors.green:Colors.orange),
   label:Text(Hive.box(hiveBoxName).get('cloudAdminPartnerName') != null
    ? 'Admin Mode • ${Hive.box(hiveBoxName).get('cloudAdminPartnerName')}'
    : (_syncMessage ?? (box.get('cloudToken') != null ? 'Cloud sync' : 'Local data')))),
  if (CloudSyncService.configured && box.get('cloudToken') != null)
   IconButton(tooltip:'Sync now', onPressed:_syncOnStart, icon:const Icon(Icons.sync)),
  if (Hive.box(hiveBoxName).get('cloudAdminToken') != null)
   IconButton(tooltip:'Return to Super Admin', onPressed:_returnToAdmin, icon:const Icon(Icons.admin_panel_settings,color:Color(0xFFB88919))),
  if (CloudSyncService.configured && box.get('cloudToken') != null)
   IconButton(tooltip:'Logout', onPressed:_logout, icon:const Icon(Icons.logout)),
  const SizedBox(width:8),
  const CircleAvatar(backgroundColor:Color(0xFFE9EFFB),child:Text('P',style:TextStyle(color:Color(0xFFD6A52A),fontWeight:FontWeight.bold))),
 ]));
 Widget _bottomNav()=>NavigationBar(
  selectedIndex:selected==0?0:selected==1?1:2,
  onDestinationSelected:(i){
   if(i==0){setState(()=>selected=0);}
   else if(i==1){setState(()=>selected=1);}
   else if(i==2){setState(()=>selected=4);}
   else if(i==3){_showMoreModules();}
   else {_showMoreModules();}
  },
  destinations:const[
   NavigationDestination(icon:Icon(Icons.dashboard),label:'Home'),
   NavigationDestination(icon:Icon(Icons.shopping_bag),label:'Orders'),
   NavigationDestination(icon:Icon(Icons.more_horiz),label:'More'),
  ],
 );
 Future<void> _showMoreModules()async{
  final options=modules.asMap().entries.where((e)=>e.key!=0&&e.key!=1&&e.key!=3&&e.key!=4).toList();
  final choice=await showModalBottomSheet<int>(context:context,builder:(c)=>SafeArea(child:ListView(shrinkWrap:true,children:[
   const ListTile(title:Text('More sections',style:TextStyle(fontWeight:FontWeight.bold))),
   ...options.map((e)=>ListTile(leading:const Icon(Icons.folder_open),title:Text(e.value),onTap:()=>Navigator.pop(c,e.key))),
  ])));
  if(choice!=null&&mounted)setState(()=>selected=choice);
 }

  String _moduleTitle(String module)=>module=='Vendor Payment Transactions'?'Vendor Pending Payment':module;
  String _fyLabel(int y)=>'$y-${(y+1).toString().substring(2)}';
  DateTime? _dateOf(Map r){
   for(final key in ['Date','Payment Date','Month']){
    final value='${r[key]??''}'.trim();
    if(value.isEmpty||value.toLowerCase().contains('not detected'))continue;
    final parsed=DateTime.tryParse(value.length==7?'$value-01':value);
    if(parsed!=null)return parsed;
   }
   return null;
  }
  List<Map> _periodRows(String module)=>rows(module).where((r){final d=_dateOf(r);if(d==null)return selectedMonth==0;final fy=d.month>=4?d.year:d.year-1;return fy==selectedFyStart&&(selectedMonth==0||d.month==selectedMonth);}).toList();
  String get _periodLabel=>selectedMonth==0?'FY ${_fyLabel(selectedFyStart)}':'${['','January','February','March','April','May','June','July','August','September','October','November','December'][selectedMonth]} ${selectedFyStart+(selectedMonth>=4?0:1)}';
  Widget _periodFilterBar(){
   final now=DateTime.now(),currentFy=now.month>=4?now.year:now.year-1;
   final years=<int>{selectedFyStart,currentFy};
   for(final m in fields.keys){for(final r in rows(m)){final d=_dateOf(r);if(d!=null)years.add(d.month>=4?d.year:d.year-1);}}
   final sorted=years.toList()..sort((a,b)=>b.compareTo(a));
   return Container(color:Colors.white,padding:const EdgeInsets.fromLTRB(18,9,18,9),child:Row(children:[
    Container(padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:const Color(0xFFFFF5D9),borderRadius:BorderRadius.circular(10)),child:const Icon(Icons.calendar_month_rounded,color:Color(0xFF9B7417),size:19)),
    const SizedBox(width:10),
    const Text('Financial year',style:TextStyle(fontSize:11,color:Colors.black54,fontWeight:FontWeight.w600)),
    const SizedBox(width:6),
    DropdownButtonHideUnderline(child:DropdownButton<int>(value:sorted.contains(selectedFyStart)?selectedFyStart:currentFy,isDense:true,borderRadius:BorderRadius.circular(12),items:sorted.map((y)=>DropdownMenuItem(value:y,child:Text('FY ${_fyLabel(y)}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:12)))).toList(),onChanged:(v){if(v!=null)setState(()=>selectedFyStart=v);})),
    const SizedBox(width:16),
    const Text('Month',style:TextStyle(fontSize:11,color:Colors.black54,fontWeight:FontWeight.w600)),
    const SizedBox(width:6),
    DropdownButtonHideUnderline(child:DropdownButton<int>(value:selectedMonth,isDense:true,borderRadius:BorderRadius.circular(12),items:[const DropdownMenuItem(value:0,child:Text('All months')),...List.generate(12,(i)=>DropdownMenuItem(value:i+1,child:Text(['January','February','March','April','May','June','July','August','September','October','November','December'][i])))],onChanged:(v){if(v!=null)setState(()=>selectedMonth=v);})),
    const Spacer(),
    Container(padding:const EdgeInsets.symmetric(horizontal:11,vertical:7),decoration:BoxDecoration(color:const Color(0xFFFFF8E8),borderRadius:BorderRadius.circular(9)),child:Text(_periodLabel,style:const TextStyle(fontSize:11,color:Color(0xFF8A6818),fontWeight:FontWeight.bold))),
   ]));
  }
  num _total(List<Map> data,String field)=>data.fold<num>(0,(v,r)=>v+(num.tryParse('${r[field]??0}'.replaceAll(',',''))??0));
  num _returnQty(List<Map> data,String type)=>data.where((r)=>'${r['RTO / Return']??''}'.toLowerCase()==type.toLowerCase()).fold<num>(0,(v,r)=>v+(num.tryParse('${r['Details']??0}'.replaceAll(',',''))??0));
  Widget _financialReportsPage(){
   final o=_periodRows('Daily Orders'),ret=_periodRows('Returns & RTO'),v=_periodRows('Vendor Payments'),b=_periodRows('Bank Received'),e=_periodRows('Expenses'),p=_periodRows('Vendor Payment Transactions');
   final sales=_total(o,'Delivered Sales'),fees=_total(o,'Commission / Fees')+_total(o,'Shipping Fees')+_total(o,'Other Deductions'),expenses=_total(e,'Expense'),bank=_total(b,'Amount'),paid=_total(p,'Amount'),purchase=_total(v,'New Amount'),opening=_total(_periodRows('Opening Balances'),'Opening Balance');
   final returns=_returnQty(ret,'Return'),rto=_returnQty(ret,'RTO'),orders=_total(o,'Orders Qty'),delivered=(orders-returns-rto).clamp(0,double.infinity);
   Widget line(String k,num n)=>Padding(padding:const EdgeInsets.symmetric(vertical:7),child:Row(children:[Expanded(child:Text(k,style:const TextStyle(fontSize:13))),Text(money(n),style:const TextStyle(fontWeight:FontWeight.w700,fontSize:13))]));
   Widget panel(String title,IconData icon,List<Widget> children)=>Card(elevation:0,color:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),side:const BorderSide(color:Color(0xFFE9E5DC))),child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Icon(icon,color:const Color(0xFFB88919)),const SizedBox(width:9),Text(title,style:const TextStyle(fontSize:14,fontWeight:FontWeight.bold,letterSpacing:.3))]),const Divider(height:24),...children])));
   final marketplace=<Widget>[];
   for(final platform in platforms){
    final total=o.where((r)=>'${r['Platform']??''}'.toLowerCase()==platform.toLowerCase()).fold<num>(0,(x,r)=>x+(num.tryParse('${r['Orders Qty']??0}')??0));
    final pr=_returnQty(ret.where((r)=>'${r['Platform']??''}'.toLowerCase()==platform.toLowerCase()).toList(),'Return');
    final pt=_returnQty(ret.where((r)=>'${r['Platform']??''}'.toLowerCase()==platform.toLowerCase()).toList(),'RTO');
    marketplace.add(Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Row(children:[Expanded(flex:2,child:Text(platform,style:const TextStyle(fontWeight:FontWeight.w700))),Expanded(child:Text('Orders ${total.toStringAsFixed(0)}',style:const TextStyle(fontSize:11))),Expanded(child:Text('Delivered ${(total-pr-pt).clamp(0,double.infinity).toStringAsFixed(0)}',style:const TextStyle(fontSize:11,color:Color(0xFF16865B)))),Expanded(child:Text('Return ${pr.toStringAsFixed(0)}',style:const TextStyle(fontSize:11,color:Color(0xFFD65A5A)))),Expanded(child:Text('RTO ${pt.toStringAsFixed(0)}',style:const TextStyle(fontSize:11,color:Color(0xFFB76A3C))))])));
   }
   return ListView(padding:const EdgeInsets.fromLTRB(20,18,20,28),children:[
    Row(children:[const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Financial Overview',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold,color:Color(0xFF17233D))),Text('Business performance and cash position',style:TextStyle(fontSize:12,color:Colors.black54))])),OutlinedButton.icon(onPressed:_exportFinancialExcel,icon:const Icon(Icons.table_view),label:const Text('Excel')),const SizedBox(width:8),FilledButton.icon(onPressed:_exportFinancialPdf,icon:const Icon(Icons.picture_as_pdf),label:const Text('PDF'))]),
    const SizedBox(height:16),
    Wrap(spacing:10,runSpacing:10,children:[_reportMetric('Total Parcels',orders),_reportMetric('Delivered',delivered),_reportMetric('Returns',returns),_reportMetric('RTO',rto)]),
    const SizedBox(height:14),
    panel('MARKETPLACE PERFORMANCE',Icons.storefront,marketplace),
    const SizedBox(height:14),
    panel('PROFIT & LOSS SUMMARY',Icons.account_balance_wallet,[line('Delivered Sales Revenue',sales),line('Marketplace Fees & Deductions',fees),line('Operating Expenses',expenses),const Divider(height:18),line('Operating Result before inventory cost',sales-fees-expenses),line('Vendor Purchases (shown separately)',purchase),const Text('Inventory opening/closing value is not yet recorded. Vendor purchases are shown separately and not treated as Cost of Goods Sold to avoid overstating profit.',style:TextStyle(color:Colors.deepOrange,fontSize:11,height:1.4))]),
    const SizedBox(height:14),
    panel('CASH FLOW & VENDOR PAYMENTS',Icons.payments,[line('Opening Cash / Bank Balance',opening),line('Bank Receipts Recorded',bank),line('Vendor Payments Made',paid),line('Operating Expenses',expenses),const Divider(height:18),line('Net Tracked Cash Movement',bank-paid-expenses),line('Estimated Closing Cash / Bank',opening+bank-paid-expenses),Text('${p.length} vendor payment transactions • ${b.length} bank receipts • ${e.length} expense records',style:const TextStyle(fontSize:11,color:Colors.black54))]),
    const SizedBox(height:14),
    panel('BALANCE SHEET CHECKLIST',Icons.account_balance,[line('Opening Cash / Bank entered',opening),const Text('Opening balances are entered separately by Cash or Bank account. Inventory, receivables, loans and owner capital still need their own records before a complete balance sheet can be prepared.',style:TextStyle(fontSize:12,color:Colors.black54,height:1.5))])
   ]);
  }
  Widget _reportMetric(String title,num value)=>Container(width:175,padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:11,color:Colors.black54)),Text(value.toStringAsFixed(0),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))]));
  List<String> _reportLines(){final o=_periodRows('Daily Orders'),e=_periodRows('Expenses'),b=_periodRows('Bank Received'),p=_periodRows('Vendor Payment Transactions'),v=_periodRows('Vendor Payments');final sales=_total(o,'Delivered Sales'),fees=_total(o,'Commission / Fees')+_total(o,'Shipping Fees')+_total(o,'Other Deductions'),expense=_total(e,'Expense');final ret=_periodRows('Returns & RTO');final total=_total(o,'Orders Qty'),returns=_returnQty(ret,'Return'),rto=_returnQty(ret,'RTO');final lines=<String>['DIGITECHIFIED BUSINESS MANAGER','FINANCIAL REPORT • $_periodLabel','','PROFIT & LOSS','Delivered Sales: ${money(sales)}','Marketplace Fees & Deductions: ${money(fees)}','Operating Expenses: ${money(expense)}','Operating Result before inventory cost: ${money(sales-fees-expense)}','Vendor Purchases: ${money(_total(v,'New Amount'))}','','MARKETPLACE DELIVERY SUMMARY','Platform | Orders | Delivered | Return | RTO'];for(final platform in platforms){final qty=o.where((r)=>'${r['Platform']??''}'.toLowerCase()==platform.toLowerCase()).fold<num>(0,(x,r)=>x+(num.tryParse('${r['Orders Qty']??0}')??0));final pr=_returnQty(ret.where((r)=>'${r['Platform']??''}'.toLowerCase()==platform.toLowerCase()).toList(),'Return');final rt=_returnQty(ret.where((r)=>'${r['Platform']??''}'.toLowerCase()==platform.toLowerCase()).toList(),'RTO');lines.add('$platform | $qty | ${(qty-pr-rt).clamp(0,double.infinity)} | $pr | $rt');}lines.addAll(['Total orders: $total','Total delivered: ${(total-returns-rto).clamp(0,double.infinity)}','Total returns: $returns','Total RTO: $rto','','CASH MOVEMENT','Bank Receipts: ${money(_total(b,'Amount'))}','Vendor Payments: ${money(_total(p,'Amount'))}','Operating Expenses: ${money(expense)}','Net Tracked Cash Movement: ${money(_total(b,'Amount')-_total(p,'Amount')-expense)}','Prepared by DIGITECHIFIED']);return lines;}
  Future<void> _exportFinancialPdf() async {
    PdfDocument? doc;
    try {
      doc = PdfDocument();
      doc.pageSettings.orientation = PdfPageOrientation.landscape;
      final navy = PdfSolidBrush(PdfColor(22, 35, 61));
      final gold = PdfSolidBrush(PdfColor(214, 165, 42));
      final grey = PdfSolidBrush(PdfColor(95, 105, 120));
      final white = PdfBrushes.white;
      final titleFont = PdfStandardFont(PdfFontFamily.helvetica, 19, style: PdfFontStyle.bold);
      final sectionFont = PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold);
      final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 9);
      final boldFont = PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold);
      final smallFont = PdfStandardFont(PdfFontFamily.helvetica, 8);
      final o = _periodRows('Daily Orders');
      final ret = _periodRows('Returns & RTO');
      final expenses = _periodRows('Expenses');
      final bank = _periodRows('Bank Received');
      final payments = _periodRows('Vendor Payment Transactions');
      final vendors = _periodRows('Vendor Payments');
      final sales = _total(o, 'Delivered Sales');
      final fees = _total(o, 'Commission / Fees') + _total(o, 'Shipping Fees') + _total(o, 'Other Deductions');
      final expenseTotal = _total(expenses, 'Expense');
      final purchases = _total(vendors, 'New Amount');
      final bankTotal = _total(bank, 'Amount');
      final paymentTotal = _total(payments, 'Amount');
      final orders = _total(o, 'Orders Qty');
      final returns = _returnQty(ret, 'Return');
      final rto = _returnQty(ret, 'RTO');
      final delivered = (orders - returns - rto).clamp(0, double.infinity);
      final pending = vendors.fold<num>(0, (v, r) =>
        v + (num.tryParse('${r['Closing Balance'] ?? r['Pending Amount'] ?? 0}'.toString().replaceAll(',', '')) ?? 0));

      late PdfPage page;
      late Size pageSize;
      void addPage(int pageNo) {
        page = doc!.pages.add();
        pageSize = page.getClientSize();
        page.graphics.drawRectangle(brush: navy, bounds: Rect.fromLTWH(0, 0, pageSize.width, 76));
        page.graphics.drawString('DIGITECHIFIED', PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold),
          brush: gold, bounds: Rect.fromLTWH(24, 11, 250, 14));
        page.graphics.drawString('FINANCIAL STATEMENT', titleFont, brush: white,
          bounds: Rect.fromLTWH(24, 29, 440, 28));
        page.graphics.drawString('$_periodLabel  •  Page $pageNo of 2', bodyFont, brush: white,
          bounds: Rect.fromLTWH(pageSize.width - 210, 31, 185, 18),
          format: PdfStringFormat(alignment: PdfTextAlignment.right));
      }
      double section(double y, String label) {
        page.graphics.drawRectangle(brush: gold, bounds: Rect.fromLTWH(22, y, pageSize.width - 44, 23));
        page.graphics.drawString(label, sectionFont, brush: navy,
          bounds: Rect.fromLTWH(31, y + 4, pageSize.width - 62, 15));
        return y + 31;
      }
      double line(double y, String label, String value, {bool bold = false}) {
        final font = bold ? boldFont : bodyFont;
        page.graphics.drawString(label, font, brush: grey,
          bounds: Rect.fromLTWH(32, y, pageSize.width * .66, 16));
        page.graphics.drawString(value, font, brush: navy,
          bounds: Rect.fromLTWH(pageSize.width * .70, y, pageSize.width * .25, 16),
          format: PdfStringFormat(alignment: PdfTextAlignment.right));
        return y + 21;
      }

      // Page 1: Profit & Loss and marketplace operations.
      addPage(1);
      var y = 96.0;
      y = section(y, 'PROFIT & LOSS STATEMENT');
      y = line(y, 'Delivered sales revenue', money(sales));
      y = line(y, 'Marketplace fees and deductions', money(fees));
      y = line(y, 'Operating expenses', money(expenseTotal));
      y = line(y, 'Operating result before inventory cost', money(sales - fees - expenseTotal), bold: true);
      y = line(y, 'Vendor purchases (shown separately; not treated as COGS)', money(purchases));
      y += 14;
      y = section(y, 'MARKETPLACE OPERATIONS');
      final left = 30.0;
      final tableWidth = pageSize.width - 60;
      final colWidths = [tableWidth * .32, tableWidth * .17, tableWidth * .17, tableWidth * .17, tableWidth * .17];
      final headers = ['Platform', 'Orders', 'Delivered', 'Returns', 'RTO'];
      var x = left;
      page.graphics.drawRectangle(brush: navy, bounds: Rect.fromLTWH(left, y, tableWidth, 25));
      for (var c = 0; c < headers.length; c++) {
        page.graphics.drawString(headers[c], PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold),
          brush: white, bounds: Rect.fromLTWH(x + 7, y + 6, colWidths[c] - 12, 14));
        x += colWidths[c];
      }
      y += 25;
      for (final platform in platforms) {
        final po = o.where((r) => '${r['Platform'] ?? ''}'.toLowerCase() == platform.toLowerCase()).toList();
        final pr = ret.where((r) => '${r['Platform'] ?? ''}'.toLowerCase() == platform.toLowerCase()).toList();
        final q = _total(po, 'Orders Qty');
        final rr = _returnQty(pr, 'Return');
        final rt = _returnQty(pr, 'RTO');
        final values = [platform, q.toStringAsFixed(0), (q - rr - rt).clamp(0, double.infinity).toStringAsFixed(0), rr.toStringAsFixed(0), rt.toStringAsFixed(0)];
        page.graphics.drawRectangle(pen: PdfPen(PdfColor(225, 229, 235)), bounds: Rect.fromLTWH(left, y, tableWidth, 25));
        x = left;
        for (var c = 0; c < values.length; c++) {
          page.graphics.drawString(values[c], bodyFont, brush: navy,
            bounds: Rect.fromLTWH(x + 7, y + 6, colWidths[c] - 12, 14));
          x += colWidths[c];
        }
        y += 25;
      }
      page.graphics.drawString('Figures are calculated from records entered for the selected financial period.',
        smallFont, brush: grey, bounds: Rect.fromLTWH(24, pageSize.height - 27, pageSize.width - 48, 14));

      // Page 2: Cash movement and recorded balance-sheet position.
      addPage(2);
      y = 100;
      y = section(y, 'CASH FLOW SUMMARY');
      y = line(y, 'Bank receipts recorded', money(bankTotal));
      y = line(y, 'Vendor payments made', money(paymentTotal));
      y = line(y, 'Operating expenses recorded', money(expenseTotal));
      y = line(y, 'Net tracked cash movement', money(bankTotal - paymentTotal - expenseTotal), bold: true);
      y += 22;
      y = section(y, 'BALANCE SHEET • RECORDED POSITION');
      y = line(y, 'Vendor payable / pending balances', money(pending));
      y = line(y, 'Vendor purchases recorded in period', money(purchases));
      y = line(y, 'Inventory opening / closing value', 'NOT RECORDED');
      y = line(y, 'Marketplace receivables / unsettled amount', 'NOT RECORDED');
      y = line(y, 'Opening bank and cash balances', 'NOT RECORDED');
      y = line(y, 'Loans and owner capital', 'NOT RECORDED');
      y += 16;
      page.graphics.drawRectangle(brush: PdfSolidBrush(PdfColor(245, 247, 250)),
        bounds: Rect.fromLTWH(24, y, pageSize.width - 48, 54));
      page.graphics.drawString('IMPORTANT NOTE', PdfStandardFont(PdfFontFamily.helvetica, 8, style: PdfFontStyle.bold),
        brush: navy, bounds: Rect.fromLTWH(34, y + 8, 150, 12));
      page.graphics.drawString('This is a recorded-position summary, not a complete statutory balance sheet. Opening balances, inventory, receivables, loans and capital are shown as NOT RECORDED when no entry exists. Vendor purchases are disclosed separately and are not assumed to be cost of goods sold.',
        smallFont, brush: grey, bounds: Rect.fromLTWH(34, y + 23, pageSize.width - 68, 26));
      page.graphics.drawString('DIGITECHIFIED BUSINESS MANAGER  •  $_periodLabel',
        smallFont, brush: grey, bounds: Rect.fromLTWH(24, pageSize.height - 27, pageSize.width - 48, 14));

      final bytes = await doc.save();
      await FileSaver.instance.saveFile(
        name: 'DIGITECHIFIED_Financial_Report_${selectedFyStart}_${selectedMonth.toString().padLeft(2, '0')}',
        bytes: Uint8List.fromList(bytes), fileExtension: 'pdf', mimeType: MimeType.pdf);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('DIGITECHIFIED Financial PDF exported')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Financial PDF export failed: $e')));
    } finally {
      doc?.dispose();
    }
  }

  Future<void> _exportFinancialExcel() async {
    try {
      final book = Excel.createExcel();
      book.rename('Sheet1', 'Overview');
      final navy = ExcelColor.fromHexString('#16233D');
      final gold = ExcelColor.fromHexString('#D6A52A');
      final pale = ExcelColor.fromHexString('#FFF5D9');
      final white = ExcelColor.fromHexString('#FFFFFF');
      final grey = ExcelColor.fromHexString('#667085');
      final titleStyle = CellStyle(bold: true, fontSize: 16, fontColorHex: white, backgroundColorHex: navy, verticalAlign: VerticalAlign.Center);
      final sectionStyle = CellStyle(bold: true, fontSize: 11, fontColorHex: navy, backgroundColorHex: pale);
      final headerStyle = CellStyle(bold: true, fontColorHex: white, backgroundColorHex: navy, textWrapping: TextWrapping.WrapText, verticalAlign: VerticalAlign.Center);
      final normalStyle = CellStyle(fontSize: 10, fontColorHex: grey, textWrapping: TextWrapping.WrapText, verticalAlign: VerticalAlign.Center);
      final valueStyle = CellStyle(fontSize: 10, bold: true, horizontalAlign: HorizontalAlign.Right, verticalAlign: VerticalAlign.Center);
      void put(Sheet sh, int row, int col, String value, CellStyle style) {
        final cell = sh.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
        cell.value = TextCellValue(value);
        cell.cellStyle = style;
      }
      void sectionRow(Sheet sh, int row, String title, int columns) {
        put(sh, row, 0, title, sectionStyle);
        for (var c = 1; c < columns; c++) put(sh, row, c, '', sectionStyle);
      }
      void twoCol(Sheet sh, int row, String label, String value, {bool bold = false}) {
        put(sh, row, 0, label, normalStyle);
        put(sh, row, 1, value, bold ? valueStyle : normalStyle);
      }
      Sheet makeTable(String name, List<String> headers, List<List<String>> rowsData) {
        final sh = book[name];
        put(sh, 0, 0, 'DIGITECHIFIED BUSINESS MANAGER', titleStyle);
        for (var c = 1; c < headers.length; c++) put(sh, 0, c, '', titleStyle);
        put(sh, 1, 0, '$name • $_periodLabel', sectionStyle);
        for (var c = 1; c < headers.length; c++) put(sh, 1, c, '', sectionStyle);
        for (var c = 0; c < headers.length; c++) put(sh, 3, c, headers[c], headerStyle);
        for (var r = 0; r < rowsData.length; r++) {
          for (var c = 0; c < headers.length; c++) put(sh, r + 4, c, c < rowsData[r].length ? rowsData[r][c] : '', normalStyle);
        }
        for (var c = 0; c < headers.length; c++) sh.setColumnWidth(c, c == 0 ? 20 : 18);
        return sh;
      }
      final o = _periodRows('Daily Orders'), ret = _periodRows('Returns & RTO');
      final expenses = _periodRows('Expenses'), bank = _periodRows('Bank Received');
      final payments = _periodRows('Vendor Payment Transactions'), vendors = _periodRows('Vendor Payments');
      final sales = _total(o, 'Delivered Sales');
      final fees = _total(o, 'Commission / Fees') + _total(o, 'Shipping Fees') + _total(o, 'Other Deductions');
      final expenseTotal = _total(expenses, 'Expense');
      final purchases = _total(vendors, 'New Amount');
      final bankTotal = _total(bank, 'Amount');
      final paymentTotal = _total(payments, 'Amount');
      final orders = _total(o, 'Orders Qty'), returns = _returnQty(ret, 'Return'), rto = _returnQty(ret, 'RTO');
      final delivered = (orders - returns - rto).clamp(0, double.infinity);
      final overview = book['Overview'];
      put(overview, 0, 0, 'DIGITECHIFIED BUSINESS MANAGER', titleStyle);
      put(overview, 1, 0, 'FINANCIAL REPORT • $_periodLabel', sectionStyle);
      sectionRow(overview, 3, 'KEY BUSINESS METRICS', 4);
      final metrics = [['Total Orders', orders.toStringAsFixed(0)], ['Delivered', delivered.toStringAsFixed(0)], ['Returns', returns.toStringAsFixed(0)], ['RTO', rto.toStringAsFixed(0)]];
      for (var i = 0; i < metrics.length; i++) { twoCol(overview, 4 + i, metrics[i][0], metrics[i][1], bold: true); }
      sectionRow(overview, 10, 'PROFIT & LOSS', 4);
      twoCol(overview, 11, 'Delivered sales revenue', money(sales));
      twoCol(overview, 12, 'Marketplace fees and deductions', money(fees));
      twoCol(overview, 13, 'Operating expenses', money(expenseTotal));
      twoCol(overview, 14, 'Operating result before inventory cost', money(sales - fees - expenseTotal), bold: true);
      twoCol(overview, 15, 'Vendor purchases (shown separately)', money(purchases));
      sectionRow(overview, 18, 'CASH FLOW', 4);
      twoCol(overview, 19, 'Bank receipts', money(bankTotal));
      twoCol(overview, 20, 'Vendor payments', money(paymentTotal));
      twoCol(overview, 21, 'Operating expenses', money(expenseTotal));
      twoCol(overview, 22, 'Net tracked cash movement', money(bankTotal - paymentTotal - expenseTotal), bold: true);
      sectionRow(overview, 25, 'BALANCE SHEET – RECORDED POSITION', 4);
      twoCol(overview, 26, 'Vendor pending balances', money(vendors.fold<num>(0, (v, r) => v + (num.tryParse('${r['Closing Balance'] ?? r['Pending Amount'] ?? 0}') ?? 0))));
      twoCol(overview, 27, 'Inventory / receivables / opening cash / loans / capital', 'NOT RECORDED');
      for (var c = 0; c < 4; c++) overview.setColumnWidth(c, c == 0 ? 48 : 22);
      makeTable('Marketplace', ['Platform', 'Orders', 'Delivered', 'Returns', 'RTO'], platforms.map((platform) {
        final po = o.where((r) => '${r['Platform'] ?? ''}'.toLowerCase() == platform.toLowerCase()).toList();
        final pr = ret.where((r) => '${r['Platform'] ?? ''}'.toLowerCase() == platform.toLowerCase()).toList();
        final q = _total(po, 'Orders Qty'), rr = _returnQty(pr, 'Return'), rt = _returnQty(pr, 'RTO');
        return [platform, q.toStringAsFixed(0), (q - rr - rt).clamp(0, double.infinity).toStringAsFixed(0), rr.toStringAsFixed(0), rt.toStringAsFixed(0)];
      }).toList());
      makeTable('P&L', ['Particulars', 'Amount'], [
        ['Delivered sales revenue', money(sales)], ['Marketplace fees & deductions', money(fees)], ['Operating expenses', money(expenseTotal)],
        ['Operating result before inventory cost', money(sales - fees - expenseTotal)], ['Vendor purchases (not treated as COGS)', money(purchases)]
      ]);
      makeTable('Balance Sheet', ['Particulars', 'Recorded value / status'], [
        ['Vendor pending balances', money(vendors.fold<num>(0, (v, r) => v + (num.tryParse('${r['Closing Balance'] ?? r['Pending Amount'] ?? 0}') ?? 0)))],
        ['Inventory opening / closing', 'NOT RECORDED'], ['Marketplace receivables', 'NOT RECORDED'],
        ['Opening bank / cash', 'NOT RECORDED'], ['Loans', 'NOT RECORDED'], ['Owner capital', 'NOT RECORDED']
      ]);
      makeTable('Cash Flow', ['Particulars', 'Amount'], [
        ['Bank receipts', money(bankTotal)], ['Vendor payments', money(paymentTotal)], ['Operating expenses', money(expenseTotal)],
        ['Net tracked cash movement', money(bankTotal - paymentTotal - expenseTotal)]
      ]);
      makeTable('Daily Orders', fields['Daily Orders']!, o.map((r) => fields['Daily Orders']!.map((c) => '${r[c] ?? ''}').toList()).toList());
      makeTable('Returns & RTO', fields['Returns & RTO']!, ret.map((r) => fields['Returns & RTO']!.map((c) => '${r[c] ?? ''}').toList()).toList());
      makeTable('Bank Received', fields['Bank Received']!, bank.map((r) => fields['Bank Received']!.map((c) => '${r[c] ?? ''}').toList()).toList());
      makeTable('Expenses', fields['Expenses']!, expenses.map((r) => fields['Expenses']!.map((c) => '${r[c] ?? ''}').toList()).toList());
      makeTable('Vendor Payments', fields['Vendor Payment Transactions']!, payments.map((r) => fields['Vendor Payment Transactions']!.map((c) => '${r[c] ?? ''}').toList()).toList());
      final bytes = book.encode();
      if (bytes == null) throw Exception('Excel workbook could not be generated');
      await FileSaver.instance.saveFile(name: 'DIGITECHIFIED_Financial_Report_${selectedFyStart}_${selectedMonth.toString().padLeft(2, '0')}', bytes: Uint8List.fromList(bytes), fileExtension: 'xlsx', mimeType: MimeType.microsoftExcel);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('DIGITECHIFIED Financial Excel exported')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Financial Excel export failed: $e')));
    }
  }

  Future<void> _exportPdf(String module) async {
    PdfDocument? doc;
    try {
      final data = _periodRows(module);
      final allCols = fields[module] ?? [];
      final columns = module == 'Daily Orders'
          ? ['Date','Platform','Firm / Account','Order ID','SKU / Product','Brand','Size','Color','Orders Qty','Gross Order Value','Delivered Qty','Delivered Sales','Commission / Fees','Shipping Fees','Courier','AWB / Tracking No.']
          : allCols;
      doc = PdfDocument();
      doc.pageSettings.orientation = PdfPageOrientation.landscape;
      final page = doc.pages.add();
      final pageSize = page.getClientSize();
      final navy = PdfSolidBrush(PdfColor(22, 35, 61));
      final gold = PdfSolidBrush(PdfColor(214, 165, 42));
      final white = PdfBrushes.white;
      final title = PdfStandardFont(PdfFontFamily.helvetica, 18, style: PdfFontStyle.bold);
      final sub = PdfStandardFont(PdfFontFamily.helvetica, 9);
      page.graphics.drawRectangle(brush: navy, bounds: Rect.fromLTWH(0, 0, pageSize.width, 68));
      page.graphics.drawString('DIGITECHIFIED', PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold), brush: gold, bounds: Rect.fromLTWH(22, 10, 220, 14));
      page.graphics.drawString(module.toUpperCase(), title, brush: white, bounds: Rect.fromLTWH(22, 27, pageSize.width - 260, 25));
      page.graphics.drawString('$_periodLabel   •   Records: ${data.length}', sub, brush: white, bounds: Rect.fromLTWH(pageSize.width - 220, 30, 200, 18), format: PdfStringFormat(alignment: PdfTextAlignment.right));
      final grid = PdfGrid();
      grid.columns.add(count: columns.length);
      final header = grid.headers.add(1)[0];
      for (var i = 0; i < columns.length; i++) { header.cells[i].value = columns[i]; }
      header.style.backgroundBrush = navy;
      header.style.textBrush = white;
      header.style.font = PdfStandardFont(PdfFontFamily.helvetica, module == 'Daily Orders' ? 5.5 : 9, style: PdfFontStyle.bold);
      for (final record in data) {
        final row = grid.rows.add();
        for (var i = 0; i < columns.length; i++) {
          row.cells[i].value = '${record[columns[i]] ?? ''}';
        }
      }
      grid.style = PdfGridStyle(
        font: PdfStandardFont(PdfFontFamily.helvetica, module == 'Daily Orders' ? 5.2 : 9),
        cellPadding: PdfPaddings(left: module == 'Daily Orders' ? 2 : 6, right: module == 'Daily Orders' ? 2 : 6, top: 4, bottom: 4),
      );
      if (module == 'Daily Orders') {
        final widths = [42,42,72,70,74,65,24,35,28,48,30,48,42,42,48,75];
        for (var i = 0; i < widths.length && i < grid.columns.count; i++) { grid.columns[i].width = widths[i].toDouble(); }
      }
      final result = grid.draw(
        page: page,
        bounds: Rect.fromLTWH(18, 82, pageSize.width - 36, pageSize.height - 102),
        format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate, breakType: PdfLayoutBreakType.fitElement),
      );
      if (result == null) throw Exception('PDF table could not be laid out');
      final bytes = await doc.save();
      await FileSaver.instance.saveFile(name: 'DIGITECHIFIED_${module.replaceAll(' ', '_').replaceAll('&', 'and')}_${selectedFyStart}_${selectedMonth.toString().padLeft(2, '0')}', bytes: Uint8List.fromList(bytes), fileExtension: 'pdf', mimeType: MimeType.pdf);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DIGITECHIFIED $module PDF exported')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$module PDF export failed: $e')));
    } finally { doc?.dispose(); }
  }

 Widget _dashboard(){
  final orderRows=_periodRows('Daily Orders');
  final orderQty=orderRows.fold<num>(0,(v,e)=>v+(num.tryParse('${e['Orders Qty']??0}')??0));
  final returnRows=_periodRows('Returns & RTO');
  final returnQty=returnRows.where((e)=>'${e['RTO / Return']??''}'.toLowerCase()=='return').fold<num>(0,(v,e)=>v+(num.tryParse('${e['Details']??0}')??0));
  final rtoQty=returnRows.where((e)=>'${e['RTO / Return']??''}'.toLowerCase()=='rto').fold<num>(0,(v,e)=>v+(num.tryParse('${e['Details']??0}')??0));
  final vendorRows=_periodRows('Vendor Payments');
  final latestVendorRows=<String,Map>{};
  for(final row in vendorRows){
   final vendor='${row['Vendor Name']??''}'.trim().toLowerCase();
   if(vendor.isEmpty)continue;
   final month='${row['Month']??''}'.trim();
   final previous=latestVendorRows[vendor];
   final previousMonth='${previous?['Month']??''}'.trim();
   if(previous==null||month.compareTo(previousMonth)>=0)latestVendorRows[vendor]=row;
  }
  final pendingVendor=latestVendorRows.values.fold<num>(0,(v,e){
   final n=num.tryParse('${e['Closing Balance']??e['Pending Amount']??e['Amount Paid']??0}'.replaceAll(',',''))??0;
   return v+(n>0?n:0);
  });
  final bankRows=_periodRows('Bank Received');
  final bankReceived=bankRows.fold<num>(0,(v,e)=>v+(num.tryParse('${e['Amount']??e['Bank Received']??e['Credit']??0}'.replaceAll(',',''))??0));
  final expenseRows=_periodRows('Expenses');
  final expenseTotal=expenseRows.fold<num>(0,(v,e)=>v+(num.tryParse('${e['Expense']??0}'.replaceAll(',',''))??0));
  final recentReturns=returnRows.reversed.take(2).toList();
  final recentBank=bankRows.reversed.take(2).toList();
  final recentExpenses=expenseRows.reversed.take(2).toList();
  final paymentRows=_periodRows('Vendor Payment Transactions');
  final recentPayments=paymentRows.reversed.take(3).toList();
  Widget metricLink(String label,num value,IconData icon,Color color,bool currency,int page)=>
   InkWell(borderRadius:BorderRadius.circular(16),onTap:()=>setState(()=>selected=page),child:_metric(label,value,icon,color,currency));
  Widget recentCard(String title,IconData icon,List<Map> data,int page,String Function(Map) primary,String Function(Map) secondary){
   return Expanded(child:InkWell(borderRadius:BorderRadius.circular(14),onTap:()=>setState(()=>selected=page),child:Container(
    padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(14),border:Border.all(color:const Color(0xFFE8ECF4))),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Row(children:[Icon(icon,size:17,color:const Color(0xFFD6A52A)),const SizedBox(width:7),Expanded(child:Text(title,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:13))),Text('View all',style:TextStyle(fontSize:10,color:Colors.blue.shade700))]),
     const SizedBox(height:7),
     if(data.isEmpty)const Text('No entries yet',style:TextStyle(fontSize:11,color:Colors.black45))
     else ...data.map((e)=>Padding(padding:const EdgeInsets.only(top:5),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(primary(e),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600)),
      Text(secondary(e),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,color:Colors.black54)),
     ]))),
    ]),
   )));
  }
  return LayoutBuilder(builder:(context, constraints){
   final compact=constraints.maxHeight<760;
   return Padding(padding:EdgeInsets.all(compact?14:20),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Text('Business Overview',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold,color:Color(0xFF17233D))),
     Text('Live summary from all your business entries',style:TextStyle(fontSize:12,color:Colors.black54)),
    ])),FilledButton.icon(onPressed:_quickAdd,icon:const Icon(Icons.add,size:18),label:const Text('Quick Entry'))]),
    SizedBox(height:compact?10:16),
    Expanded(flex:5,child:LayoutBuilder(builder:(context,c){
     final count=c.maxWidth>1200?4:(c.maxWidth>560?3:2);
     final cardHeight=compact?78.0:92.0;
     final deliveredQty=(orderQty-returnQty-rtoQty).clamp(0,double.infinity);
     final cards=[
      metricLink('Total Orders',orderQty,Icons.shopping_bag_outlined,const Color(0xFFD6A52A),false,1),
      metricLink('Delivered',deliveredQty,Icons.check_circle_outline,const Color(0xFF16865B),false,1),
      metricLink('Returns',returnQty,Icons.assignment_return,const Color(0xFFD65A5A),false,2),
      metricLink('RTO',rtoQty,Icons.undo,const Color(0xFFB76A3C),false,2),
      metricLink('Vendor Payments Made',_total(paymentRows,'Amount'),Icons.payments,const Color(0xFF8A5BD1),true,7),
      metricLink('Bank Received',bankReceived,Icons.account_balance,const Color(0xFF16865B),true,4),
      metricLink('Expenses',expenseTotal,Icons.receipt_long,const Color(0xFFDA8B25),true,5),
     ];
     return GridView.count(crossAxisCount:count,childAspectRatio:c.maxWidth/count/cardHeight,mainAxisSpacing:9,crossAxisSpacing:9,physics:const NeverScrollableScrollPhysics(),children:cards);
    })),
    SizedBox(height:compact?8:14),
    Row(children:[const Expanded(child:Text('Marketplace performance',style:TextStyle(fontSize:15,fontWeight:FontWeight.bold))),Text('${orderRows.length} SKU records',style:const TextStyle(fontSize:10,color:Colors.black54))]),
    const SizedBox(height:6),
    SizedBox(height:compact?92:104,child:Row(children:platforms.map((p){
     final list=orderRows.where((e)=>'${e['Platform']??''}'.toLowerCase()==p.toLowerCase()).toList();
     final qty=list.fold<num>(0,(v,e)=>v+(num.tryParse('${e['Orders Qty']??0}')??0));
     final platformReturns=returnRows.where((e)=>'${e['Platform']??'Unknown'}'.toLowerCase()==p.toLowerCase()&&'${e['RTO / Return']??''}'.toLowerCase()=='return').fold<num>(0,(v,e)=>v+(num.tryParse('${e['Details']??0}')??0));
     final platformRto=returnRows.where((e)=>'${e['Platform']??'Unknown'}'.toLowerCase()==p.toLowerCase()&&'${e['RTO / Return']??''}'.toLowerCase()=='rto').fold<num>(0,(v,e)=>v+(num.tryParse('${e['Details']??0}')??0));
     final delivered=(qty-platformReturns-platformRto).clamp(0,double.infinity);
     return Expanded(child:Padding(padding:const EdgeInsets.only(right:6),child:InkWell(onTap:()=>setState(()=>selected=1),borderRadius:BorderRadius.circular(10),child:Container(padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(10),border:Border.all(color:const Color(0xFFE8ECF4))),child:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(p,style:const TextStyle(fontSize:11,fontWeight:FontWeight.bold),maxLines:1,overflow:TextOverflow.ellipsis),
      Text('Delivered ${delivered.toStringAsFixed(0)}',style:const TextStyle(fontSize:10,color:Color(0xFF16865B))),
      Text('Return ${platformReturns.toStringAsFixed(0)} • RTO ${platformRto.toStringAsFixed(0)}',style:const TextStyle(fontSize:9,color:Colors.black54)),
     ])))));
    }).toList())),
    SizedBox(height:compact?8:12),
    Expanded(flex:3,child:Row(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
     recentCard('Returns & RTO',Icons.assignment_return,recentReturns,2,(e)=>'${e['RTO / Return']??'Return'} • ${e['Details']??''}',(e)=>'${e['Date']??''}'),
     const SizedBox(width:8),
     recentCard('Bank Received',Icons.account_balance,recentBank,4,(e)=>'${e['Platform']??e['Firm / Account']??'Bank entry'} • ₹${e['Amount']??e['Credit']??e['Bank Received']??0}',(e)=>'${e['Date']??''}'),
     const SizedBox(width:8),
     recentCard('Expenses',Icons.receipt_long,recentExpenses,5,(e)=>'${e['Expense']??0} • ${e['Details']??''}',(e)=>'${e['Date']??''}'),
     const SizedBox(width:8),
     recentCard('Vendor Pending Payment',Icons.payments,recentPayments,7,(e)=>'${e['Vendor Name']??'Vendor'} • ₹${e['Amount']??0}',(e)=>'${e['Date']??''} • ${e['Payment Mode']??''}'),
    ])),
   ]));
  });
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
  final allData=_periodRows(module),cols=fields[module]??[];
  final isDaily=module=='Daily Orders';
  final query=isDaily?_dailySearchController.text.trim().toLowerCase():'';
  final filtered=isDaily&&query.isNotEmpty
    ? allData.where((row)=>row.values.any((v)=>'$v'.toLowerCase().contains(query))).toList()
    : allData;
  final pageCount=(filtered.length/_dailyPageSize).ceil();
  if(isDaily&&pageCount>0&&_dailyPage>=pageCount)_dailyPage=pageCount-1;
  if(isDaily&&_dailyPage<0)_dailyPage=0;
  final startIndex=isDaily?_dailyPage*_dailyPageSize:0;
  final visible=isDaily?filtered.skip(startIndex).take(_dailyPageSize).toList():filtered;
  return ListView(padding:const EdgeInsets.all(22),children:[
   if (isDaily)
    Container(
     padding: const EdgeInsets.all(20),
     decoration: BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF090909),Color(0xFF252525)]),borderRadius:BorderRadius.circular(18)),
     child:Row(children:[
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),decoration:BoxDecoration(color:Colors.white.withOpacity(.13),borderRadius:BorderRadius.circular(20)),child:const Text('PDF-FIRST WORKFLOW',style:TextStyle(color:Color(0xFFFFC44F),fontSize:10,fontWeight:FontWeight.bold,letterSpacing:1))),
       const SizedBox(height:10),const Text('Daily Marketplace Orders',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.bold)),
       const SizedBox(height:5),const Text('Upload Myntra or Meesho shipping labels. Orders are saved instantly with date, platform and brand-wise totals.',style:TextStyle(color:Color(0xFFE8E3D5),height:1.4)),
      ])),
      const SizedBox(width:12),Container(width:54,height:54,decoration:BoxDecoration(color:const Color(0xFFFFC44F).withOpacity(.15),borderRadius:BorderRadius.circular(16)),child:const Icon(Icons.picture_as_pdf_rounded,color:Color(0xFFFFC44F),size:29)),
     ]),
    ) else Text('${allData.length} records',style:const TextStyle(color:Colors.black54)),
   const SizedBox(height:14),
   Wrap(spacing:10,runSpacing:10,children:[
    FilledButton.icon(onPressed:()=>_addRecord(module),icon:const Icon(Icons.add),label:const Text('Add Manually')),
    OutlinedButton.icon(onPressed:()=>_exportPdf(module),icon:const Icon(Icons.picture_as_pdf_outlined),label:const Text('Export PDF')), 
    if(isDaily)FilledButton.icon(onPressed:_pdfImporting?null:()=>_importShippingPdf(),icon:_pdfImporting?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Icon(Icons.picture_as_pdf_outlined),label:Text(_pdfImporting?'Importing PDF...':'Upload Shipping Label PDF')),
   ]),
   const SizedBox(height:16),
   if(isDaily)_dailyOrderSummary(allData),
   if(isDaily)...[
    const SizedBox(height:14),
    TextField(controller:_dailySearchController, onChanged:(_){setState(()=>_dailyPage=0);},
     decoration:InputDecoration(
      hintText:'Search date, platform, firm, order ID, SKU, brand, customer...',
      prefixIcon:const Icon(Icons.search,color:Color(0xFF9B7417)),
      suffixIcon:_dailySearchController.text.isEmpty?null:IconButton(icon:const Icon(Icons.close),onPressed:(){_dailySearchController.clear();setState(()=>_dailyPage=0);}),
      filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:const BorderSide(color:Color(0xFFE5DFD2))),
     )),
    const SizedBox(height:8),
    Row(children:[
     Expanded(child:Text('${filtered.length} records found • Showing ${filtered.isEmpty?0:startIndex+1}-${(startIndex+visible.length)}',style:const TextStyle(color:Colors.black54,fontSize:12))),
     const Text('100 per page',style:TextStyle(color:Color(0xFF8A6818),fontSize:12,fontWeight:FontWeight.w600)),
    ]),
   ],
   if(filtered.isEmpty)Container(padding:const EdgeInsets.all(32),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(16)),child:Column(children:[
    const Icon(Icons.inbox_outlined,size:42,color:Colors.black38),const SizedBox(height:10),
    Text(isDaily&&query.isNotEmpty?'No matching orders':'No records yet',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
    const SizedBox(height:5),const Text('Try another search or add a record.',style:TextStyle(color:Colors.black54)),
   ])) else Card(color:Colors.white,elevation:0,child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(
    columns:[...cols.take(6).map((col)=>DataColumn(label:Text(col,style:const TextStyle(fontWeight:FontWeight.bold)))),const DataColumn(label:Text('Action'))],
    rows:visible.map((row){
     final idx=allData.indexOf(row);
     return DataRow(cells:[
      ...cols.take(6).map((col)=>DataCell(Text('${row[col]??''}',maxLines:1,overflow:TextOverflow.ellipsis))),
      DataCell(Row(mainAxisSize:MainAxisSize.min,children:[
       if(module=='Vendor Payments')TextButton.icon(onPressed:()=>_recordVendorPayment(idx),icon:const Icon(Icons.payments_outlined,size:16),label:const Text('Pay')),
        IconButton(tooltip:'Edit record',icon:const Icon(Icons.edit_outlined,color:Color(0xFF2457C5)),onPressed:()=>_editRecord(module,idx)),
       IconButton(tooltip:'Delete record',icon:const Icon(Icons.delete_outline,color:Colors.red),onPressed:()=>_deleteRecord(module,idx)),
      ])),
     ]);
    }).toList(),
   ))),
   if(isDaily&&pageCount>1)Padding(padding:const EdgeInsets.symmetric(vertical:14),child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
    OutlinedButton.icon(onPressed:_dailyPage>0?()=>setState(()=>_dailyPage--):null,icon:const Icon(Icons.chevron_left),label:const Text('Previous')),
    Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Text('Page ${_dailyPage+1} of $pageCount',style:const TextStyle(fontWeight:FontWeight.w600))),
    OutlinedButton.icon(onPressed:_dailyPage<pageCount-1?()=>setState(()=>_dailyPage++):null,icon:const Icon(Icons.chevron_right),label:const Text('Next')),
   ])),
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

 Future<void> _importShippingPdf() async {
  if(_pdfImporting)return;
  String platform='Myntra';
  final selectedPlatform=await showDialog<String>(
   context:context,
   builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>Dialog(
    backgroundColor:const Color(0xFFF9F7F1),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24)),
    child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
     Row(children:[
      Container(width:48,height:48,decoration:BoxDecoration(color:const Color(0xFF080808),borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.picture_as_pdf_rounded,color:Color(0xFFFFC44F))),
      const SizedBox(width:12),const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Text('Import marketplace PDF',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold,color:Color(0xFF171717))),
       SizedBox(height:3),Text('Choose the platform for these shipping labels',style:TextStyle(fontSize:12,color:Colors.black54)),
      ])),
     ]),
     const SizedBox(height:22),
     DropdownButtonFormField<String>(value:platform,isExpanded:true,decoration:const InputDecoration(labelText:'Marketplace',prefixIcon:Icon(Icons.storefront_outlined)),items:const ['Myntra','Meesho'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)setDialog(()=>platform=v);}),
     const SizedBox(height:12),
     Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:const Color(0xFFF1EBDD),borderRadius:BorderRadius.circular(12)),child:const Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(Icons.info_outline,color:Color(0xFF8A6818),size:18),SizedBox(width:8),Expanded(child:Text('Only shipping labels are counted. Myntra brand will be saved as JIPROSTORE.',style:TextStyle(fontSize:12,color:Color(0xFF5F512F)))),
     ])),
     const SizedBox(height:18),
     Row(children:[
      Expanded(child:TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel'))),
      const SizedBox(width:10),
      Expanded(flex:2,child:FilledButton.icon(onPressed:()=>Navigator.pop(ctx,platform),icon:const Icon(Icons.folder_open_rounded),label:const Text('Choose PDF'))),
     ]),
    ])),
   )),
  );
  if(selectedPlatform==null)return;
  final picked=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['pdf'],withData:true);
  if(picked==null)return;
  final bytes=picked.files.single.bytes;
  if(bytes==null||bytes.isEmpty){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('PDF file could not be read. Please choose it again.')));
   return;
  }
  setState(()=>_pdfImporting=true);
  showDialog<void>(context:context,barrierDismissible:false,builder:(ctx)=>PopScope(canPop:false,child:Dialog(
   backgroundColor:const Color(0xFFF9F7F1),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22)),
   child:Padding(padding:const EdgeInsets.all(26),child:Column(mainAxisSize:MainAxisSize.min,children:[
    const SizedBox(width:42,height:42,child:CircularProgressIndicator(strokeWidth:3,color:Color(0xFFD6A52A))),
    const SizedBox(height:18),const Text('Reading shipping labels...',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
    const SizedBox(height:6),Text('Processing ${picked.files.single.name}',textAlign:TextAlign.center,style:const TextStyle(color:Colors.black54,fontSize:12)),
    const SizedBox(height:4),const Text('Please wait. Do not close this window.',style:TextStyle(color:Colors.black54,fontSize:11)),
   ])),
  )));
  await Future<void>.delayed(const Duration(milliseconds:120));
  try{
   final imported=selectedPlatform=='Myntra'?MyntraLabelParser.parse(bytes):MeeshoLabelParser.parse(bytes);
   if(imported.isEmpty)throw Exception('No shipping labels detected. Please check the selected PDF.');
   final existing=rows('Daily Orders');
   final sourceName=picked.files.single.name;
   final today=DateTime.now();
   final importDate='${today.year.toString().padLeft(4,'0')}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
   for(final item in imported){
    item['Source PDF']=sourceName;
    item['Label ID']='$sourceName-${item['Label ID']}';
    if(selectedPlatform=='Myntra'){
     item['Brand']='JIPROSTORE';
     final parsedDate='${item['Date']??''}'.trim();
     if(parsedDate.isEmpty||parsedDate=='Not detected')item['Date']=importDate;
    }
   }
   final knownLabels=existing.map((e)=>'${e['Label ID']??''}').toSet();
   imported.removeWhere((e)=>knownLabels.contains('${e['Label ID']}'));
   if(imported.isEmpty)throw Exception('This PDF has already been imported.');
   await saveRows('Daily Orders',[...existing,...imported]);
   if(mounted){
    setState(()=>_dailyPage=0);
    final labelCount=imported.map((e)=>e['Label ID']).toSet().length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$labelCount shipping labels and ${imported.length} SKU rows added. Daily Orders updated.')));
   }
  }catch(e){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('PDF import failed: ${e.toString().replaceFirst('Exception: ','')}')));
  }finally{
   if(mounted){
    Navigator.of(context,rootNavigator:true).pop();
    setState(()=>_pdfImporting=false);
   }
  }
 }

 Future<void> _quickAdd()async{
  final choice=await showModalBottomSheet<String>(context:context,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
   const ListTile(title:Text('Quick Entry',style:TextStyle(fontWeight:FontWeight.bold))),
   ...['Daily Orders','Returns & RTO','Bank Received','Expenses'].map((v)=>ListTile(title:Text(v),leading:const Icon(Icons.add_circle_outline),onTap:()=>Navigator.pop(c,v))),
  ])));
  if(choice!=null)_addRecord(choice);
 }
 Future<void> _addRecord(String module)async{
  final controllers=<String,TextEditingController>{};
  for(final f in fields[module]??[])controllers[f]=TextEditingController();
  for(final f in ['Date','Purchase Date','Payment Date','Settlement Date']){if(controllers.containsKey(f))controllers[f]!.text=DateTime.now().toIso8601String().substring(0,10);}
  if((module=='Vendor Payments'||module=='Vendor Payment Transactions')&&controllers.containsKey('Month')){final now=DateTime.now();controllers['Month']!.text='${now.year}-${now.month.toString().padLeft(2,'0')}';if(controllers.containsKey('Payment Date'))controllers['Payment Date']!.text=now.toIso8601String().substring(0,10);}
  if(controllers.containsKey('Platform'))controllers['Platform']!.text=module=='Returns & RTO'?'Meesho':'Myntra';
  if(module=='Opening Balances' && controllers.containsKey('Account Type'))controllers['Account Type']!.text='Bank';
  if(controllers.containsKey('Brand'))controllers['Brand']!.text='JIPROSTORE';
  final ok=await showDialog<bool>(context:context,builder:(ctx)=>Dialog(
   backgroundColor:const Color(0xFFF9F7F1),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24)),
   child:SizedBox(width:MediaQuery.of(ctx).size.width*.9,height:MediaQuery.of(ctx).size.height*.78,child:Padding(padding:const EdgeInsets.all(22),child:Column(mainAxisSize:MainAxisSize.max,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[Container(width:44,height:44,decoration:BoxDecoration(color:const Color(0xFF111111),borderRadius:BorderRadius.circular(13)),child:const Icon(Icons.edit_note_rounded,color:Color(0xFFFFC84D),size:26)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Add ${_moduleTitle(module)}',style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold)),Text(module=='Bank Received'?'Record marketplace bank receipt':'Enter $module details below',style:const TextStyle(color:Colors.black54,fontSize:12))]))]),
    const SizedBox(height:16),
    Expanded(child:SingleChildScrollView(child:Column(children:controllers.entries.map((e)=>Padding(padding:const EdgeInsets.only(bottom:12),child:_formField(module,e.key,e.value))).toList()))),
    const SizedBox(height:10),
    Row(children:[Expanded(child:TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel'))),const SizedBox(width:8),Expanded(child:FilledButton.icon(onPressed:()=>Navigator.pop(ctx,true),icon:const Icon(Icons.save_rounded),label:const Text('Save Record')))])
   ]))),
  ));
  if(ok==true){
   final record=<String,dynamic>{for(final e in controllers.entries)e.key:e.value.text.trim()};
   if(module=='Vendor Payments'){
    final vendor="${record['Vendor Name']??''}".trim().toLowerCase();
    final month="${record['Month']??''}".trim();
    num previous=0;String previousMonth='';
    for(final old in rows('Vendor Payments')){
     if("${old['Vendor Name']??''}".trim().toLowerCase()!=vendor)continue;
     final oldMonth="${old['Month']??''}".trim();
     if((oldMonth.isEmpty||oldMonth.compareTo(month)<=0)&&oldMonth.compareTo(previousMonth)>=0){
      previousMonth=oldMonth;
      previous=num.tryParse("${old['Closing Balance']??old['Pending Amount']??old['Amount Paid']??0}".replaceAll(',',''))??0;
     }
    }
    if((record['Opening Balance']??'').toString().trim().isEmpty)record['Opening Balance']=previous.toStringAsFixed(2);
    final opening=num.tryParse("${record['Opening Balance']??0}".replaceAll(',',''))??0;
    final added=num.tryParse("${record['New Amount']??0}".replaceAll(',',''))??0;
    final paid=num.tryParse("${record['Amount Paid']??0}".replaceAll(',',''))??0;
    record['Closing Balance']=(opening+added-paid).toStringAsFixed(2);
   }
   if(record.values.every((v)=>'$v'.trim().isEmpty)){
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Please enter at least one field.')));
   }else{
    final list=rows(module)..add(record);await saveRows(module,list);
    if(mounted){setState((){});ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Record added successfully.')));}
   }
  }
  for(final controller in controllers.values){controller.dispose();}
 }

 List<String> _optionsFor(String module, String field) {
  final normalized = field.toLowerCase();
  if (normalized == 'platform') return platforms;
  if (normalized == 'vendor name' || normalized == 'vendor') {
    return rows('Vendor Payments').map((r) => '${r['Vendor Name'] ?? ''}'.trim()).where((v) => v.isNotEmpty).toSet().toList();
  }
  if (normalized.contains('firm') || normalized.contains('account') || normalized.contains('gst entity')) {
    final names = <String>{};
    for (final moduleName in ['Daily Orders','Bank Received','Vendor Payments']) {
      for (final row in rows(moduleName)) {
        for (final key in ['Firm / Account','Firm Name','Bank Account']) {
          final value = '${row[key] ?? ''}'.trim();
          if (value.isNotEmpty) names.add(value);
        }
      }
    }
    return names.toList()..sort();
  }
  if (normalized == 'type' || normalized == 'rto / return') return ['Return', 'RTO'];
  if (normalized == 'status') return ['Pending', 'Completed', 'On Hold', 'Cancelled'];
  if (normalized.contains('payment mode')) return ['Bank Transfer', 'UPI', 'Cash', 'Cheque', 'Credit', 'Other'];
  if (normalized == 'record type') return ['Firm', 'Platform', 'Vendor', 'Bank Account', 'Expense Category'];
  if (normalized == 'account type') return ['Cash', 'Bank'];
  if (normalized == 'state') return ['Gujarat', 'Maharashtra', 'Rajasthan', 'Delhi', 'Karnataka', 'Other'];
  if (normalized == 'gst %') return ['0', '5', '12', '18', '28'];
  return const [];
 }
 Widget _formField(String module, String field, TextEditingController controller) {
  if((module=='Vendor Payments' && field=='Payment Date') || ((module=='Expenses' || module=='Returns & RTO' || module=='Bank Received' || module=='Vendor Payment Transactions' || module=='Opening Balances') && field=='Date')){
   DateTime? selectedDate;
   try{selectedDate=DateTime.tryParse(controller.text);}catch(_){}
   return Padding(padding:const EdgeInsets.only(bottom:12),child:InkWell(
    onTap:()async{
     final now=DateTime.now();
     final initial=selectedDate??now;
     final picked=await showDatePicker(context:context,initialDate:initial,firstDate:DateTime(2000),lastDate:DateTime(2100),builder:(ctx,child)=>Theme(data:Theme.of(ctx).copyWith(colorScheme:const ColorScheme.light(primary:Color(0xFFD6A52A),onPrimary:Colors.black)),child:child!));
     if(picked!=null){controller.text='${picked.year.toString().padLeft(4,'0')}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}';if(mounted)setState((){});}
    },
    child:InputDecorator(decoration:InputDecoration(labelText:field,prefixIcon:const Icon(Icons.calendar_month_rounded),suffixIcon:const Icon(Icons.arrow_drop_down)),child:Text(controller.text.isEmpty?'Choose $field':controller.text,style:TextStyle(color:controller.text.isEmpty?Colors.black45:Colors.black87))),
   ));
  }
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
 bool _numeric(String key)=>['Qty','Value','Sales','Fees','Shipping','Deductions','Amount','Expense','GST %','Credit','Debit','Balance','Paid','Received'].any((v)=>key.toLowerCase().contains(v.toLowerCase()));
 Future<void> _editRecord(String module,int index) async {
  final list=rows(module);
  if(index<0||index>=list.length)return;
  final original=list[index];
  final controllers=<String,TextEditingController>{
   for(final field in fields[module]??[])
    field:TextEditingController(text:'${original[field]??(field=='Pending Amount'?original['Amount Paid']??'':'')}')
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
   final updated=<String,dynamic>{...original,for(final e in controllers.entries)e.key:e.value.text.trim()};
   if(module=='Vendor Payments'){
    final opening=num.tryParse("${updated['Opening Balance']??0}".replaceAll(',',''))??0;
    final added=num.tryParse("${updated['New Amount']??0}".replaceAll(',',''))??0;
    final paid=num.tryParse("${updated['Amount Paid']??0}".replaceAll(',',''))??0;
    updated['Closing Balance']=(opening+added-paid).toStringAsFixed(2);
    updated.remove('Pending Amount');
   }
   list[index]=updated;
   await saveRows(module,list);
   if(mounted)setState((){});
  }
  for(final c in controllers.values){c.dispose();}
 }

 Future<void> _recordVendorPayment(int index) async {
  final list=rows('Vendor Payments');
  if(index<0||index>=list.length)return;
  final row=list[index];
  final opening=num.tryParse("${row['Opening Balance']??0}".replaceAll(',',''))??0;
  final added=num.tryParse("${row['New Amount']??0}".replaceAll(',',''))??0;
  final paidBefore=num.tryParse("${row['Amount Paid']??0}".replaceAll(',',''))??0;
  final pending=num.tryParse("${row['Closing Balance']??row['Pending Amount']??(opening+added-paidBefore)}".replaceAll(',',''))??0;
  final amountController=TextEditingController();
  final noteController=TextEditingController();
  final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
   title:Text("Record payment • ${row['Vendor Name']??'Vendor'}"),
   content:Column(mainAxisSize:MainAxisSize.min,children:[
    Align(alignment:Alignment.centerLeft,child:Text('Current pending: ₹${pending.toStringAsFixed(2)}',style:const TextStyle(fontWeight:FontWeight.bold,color:Color(0xFF8A6818)))),
    const SizedBox(height:12),
    TextField(controller:amountController,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Payment amount',prefixText:'₹ ')),
    const SizedBox(height:10),
    TextField(controller:noteController,decoration:const InputDecoration(labelText:'Payment note (optional)')),
   ]),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
    FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save Payment')),
   ],
  ));
  if(ok==true){
   final paidNow=num.tryParse(amountController.text.trim().replaceAll(',',''));
   if(paidNow==null||paidNow<=0){
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter a valid payment amount.')));
   }else if(paidNow>pending){
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Payment cannot be greater than pending amount.')));
   }else{
    final updated={...row};
    final totalPaid=paidBefore+paidNow;
    final now=DateTime.now();
    final stamp="${now.year.toString().padLeft(4,'0')}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}";
    final history=(updated['_paymentHistory']??'').toString();
    updated['Amount Paid']=totalPaid.toStringAsFixed(2);
    updated['Closing Balance']=(pending-paidNow).toStringAsFixed(2);
    updated.remove('Pending Amount');
    updated['_paymentHistory']=[history,"₹${paidNow.toStringAsFixed(2)} • $stamp${noteController.text.trim().isEmpty?'':' • ${noteController.text.trim()}'}"].where((v)=>v.isNotEmpty).join('\\n');
    list[index]=updated;
    await saveRows('Vendor Payments',list);
    final paymentRows=rows('Vendor Payment Transactions')..add({'Date':stamp,'Month':'${now.year}-${now.month.toString().padLeft(2,'0')}','Firm Name':row['Firm Name']??'','Vendor Name':row['Vendor Name']??'','Amount':paidNow.toStringAsFixed(2),'Payment Mode':'Not specified','Notes':noteController.text.trim(),'_syncId':_newSyncId()});
    await saveRows('Vendor Payment Transactions',paymentRows);
    if(mounted){setState((){});ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Payment saved. Remaining pending: ₹${(pending-paidNow).toStringAsFixed(2)}')));}
   }
  }
  amountController.dispose();
  noteController.dispose();
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
   final data=_periodRows(module),cols=fields[module]??[];final book=Excel.createExcel();final sheet=book['DIGITECHIFIED'];
   sheet.appendRow([TextCellValue('DIGITECHIFIED BUSINESS MANAGER')]);
   sheet.appendRow([TextCellValue('$module • $_periodLabel')]);
   sheet.appendRow(cols.map((e)=>TextCellValue(e)).toList());
   for(final row in data){sheet.appendRow(cols.map((e)=>TextCellValue('${row[e]??''}')).toList());}
   final bytes=book.encode();if(bytes==null)return;
   await FileSaver.instance.saveFile(name:'DIGITECHIFIED_${module.replaceAll(' ','_')}_${selectedFyStart}_${selectedMonth.toString().padLeft(2,'0')}',bytes:Uint8List.fromList(bytes),fileExtension:'xlsx',mimeType:MimeType.microsoftExcel);
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('DIGITECHIFIED Excel export ready')));
  }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Export failed: $e')));}
 }

}
