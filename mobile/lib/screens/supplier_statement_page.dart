import 'package:flutter/material.dart';
import '../data/local_database.dart';
import '../data/supplier_account_operations.dart';

class SupplierStatementPage extends StatefulWidget {
  const SupplierStatementPage({required this.tr, super.key});
  final String Function(String) tr;
  @override
  State<SupplierStatementPage> createState() => _SupplierStatementPageState();
}

class _SupplierStatementPageState extends State<SupplierStatementPage> {
  List<Map<String,Object?>> _suppliers = [];
  List<Map<String,Object?>> _rows = [];
  int? _supplierId;
  DateTime? _from;
  DateTime? _to;
  Map<String,double> _balances = {'opening':0,'debit':0,'credit':0,'closing':0};
  bool _loading = true;

  String _money(double v) => v.toStringAsFixed(2);
  String _date(DateTime? d) => d == null ? '—' : d.toIso8601String().substring(0,10);

  @override
  void initState() { super.initState(); _loadSuppliers(); }

  Future<void> _loadSuppliers() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query('suppliers', where:'is_active = 1', orderBy:'name COLLATE NOCASE');
    if (!mounted) return;
    setState(() { _suppliers = rows; _supplierId = rows.isEmpty ? null : rows.first['id'] as int; });
    await _loadStatement();
  }

  Future<void> _loadStatement() async {
    final id = _supplierId;
    if (id == null) { if(mounted) setState(()=>_loading=false); return; }
    setState(()=>_loading=true);
    final db = await LocalDatabase.instance.database;
    final ops = SupplierAccountOperations(db);
    final balances = await ops.getBalances(supplierId:id, from:_from, to:_to);
    final rows = await ops.getStatement(supplierId:id, from:_from, to:_to);
    if (!mounted) return;
    setState(() { _balances=balances; _rows=rows; _loading=false; });
  }

  Future<void> _recordPayment() async {
    final id = _supplierId;
    if (id == null) return;
    final amount = TextEditingController();
    final reference = TextEditingController();
    String method='cash';
    final ok = await showDialog<bool>(context:context, builder:(ctx)=>StatefulBuilder(
      builder:(ctx,setDialog)=>AlertDialog(
        title: const Text('تسجيل دفعة للمورد'),
        content: Column(mainAxisSize:MainAxisSize.min, children:[
          TextField(controller:amount, keyboardType:const TextInputType.numberWithOptions(decimal:true),
            decoration:const InputDecoration(labelText:'المبلغ')),
          const SizedBox(height:10),
          DropdownButtonFormField<String>(value:method, decoration:const InputDecoration(labelText:'طريقة الدفع'),
            items:const [DropdownMenuItem(value:'cash',child:Text('نقداً')),DropdownMenuItem(value:'bank',child:Text('تحويل بنكي')),DropdownMenuItem(value:'cheque',child:Text('شيك'))],
            onChanged:(v)=>setDialog(()=>method=v??'cash')),
          const SizedBox(height:10),
          TextField(controller:reference, decoration:const InputDecoration(labelText:'رقم المرجع / الإيصال')),
        ]),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('حفظ الدفعة')),
        ],
      ),
    ));
    if(ok==true) {
      try {
        final value=double.tryParse(amount.text.trim());
        if(value==null || !value.isFinite || value<=0) {
          throw ArgumentError('يجب إدخال مبلغ صحيح أكبر من صفر.');
        }
        final db=await LocalDatabase.instance.database;
        await SupplierAccountOperations(db).recordPayment(
          number:'SP-${DateTime.now().millisecondsSinceEpoch}', supplierId:id,
          date:DateTime.now(), amount:value, method:method,
          reference:reference.text.trim().isEmpty?null:reference.text.trim());
        await _loadStatement();
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content:Text('تم تسجيل الدفعة وتحديث كشف الحساب.')));
      } catch(e) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذر تسجيل الدفعة: $e')));
      }
    }
    amount.dispose(); reference.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final initial = start ? (_from ?? DateTime.now()) : (_to ?? DateTime.now());
    final picked=await showDatePicker(context:context, initialDate:initial,
      firstDate:DateTime(2000), lastDate:DateTime(2100));
    if(picked==null) return;
    final candidateFrom = start ? picked : _from;
    final candidateTo = start ? _to : picked;
    if(candidateFrom!=null && candidateTo!=null && candidateFrom.isAfter(candidateTo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('تاريخ البداية يجب أن يسبق تاريخ النهاية أو يساويه.')));
      return;
    }
    setState(()=> start ? _from=picked : _to=picked);
    await _loadStatement();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed:_supplierId==null?null:_recordPayment,
        icon:const Icon(Icons.payments_outlined), label:const Text('تسجيل دفعة'),
      ),
      body: _loading ? const Center(child:CircularProgressIndicator()) :
        RefreshIndicator(onRefresh:_loadStatement, child:ListView(
          padding:const EdgeInsets.all(14), children:[
            Text('كشف حساب المورد', style:Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height:12),
            DropdownButtonFormField<int>(value:_supplierId, isExpanded:true,
              decoration:const InputDecoration(labelText:'اختر المورد'),
              items:_suppliers.map((s)=>DropdownMenuItem<int>(value:s['id'] as int,child:Text(s['name'].toString()))).toList(),
              onChanged:(v) async { setState(()=>_supplierId=v); await _loadStatement(); }),
            const SizedBox(height:10),
            Wrap(spacing:8, runSpacing:8, children:[
              OutlinedButton.icon(onPressed:()=>_pickDate(true), icon:const Icon(Icons.calendar_today), label:Text('من: ${_date(_from)}')),
              OutlinedButton.icon(onPressed:()=>_pickDate(false), icon:const Icon(Icons.event), label:Text('إلى: ${_date(_to)}')),
              TextButton(onPressed:() async { setState(() { _from=null; _to=null; }); await _loadStatement(); }, child:const Text('كل الفترة')),
            ]),
            const SizedBox(height:10),
            _balanceCard('الرصيد السابق',_balances['opening']??0),
            _balanceCard('إجمالي المدين (دفعات/مرتجعات)',_balances['debit']??0),
            _balanceCard('إجمالي الدائن (توريد)',_balances['credit']??0),
            Card(child:ListTile(title:const Text('الرصيد المستحق للمورد'), trailing:Text(_money(_balances['closing']??0),style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)))),
            const SizedBox(height:14),
            Text('تفاصيل الحركة',style:Theme.of(context).textTheme.titleMedium),
            if(_rows.isEmpty) const Padding(padding:EdgeInsets.all(20),child:Center(child:Text('لا توجد حركات في الفترة المحددة.'))),
            ..._rows.map((r)=>Card(child:ListTile(
              leading:const Icon(Icons.receipt_long_outlined),
              title:Text(_typeLabel(r['transaction_type']?.toString()??'')),
              subtitle:Text('${r['document_type']} #${r['document_id']} • ${r['transaction_date']}'),
              trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[
                if((r['debit'] as num).toDouble()>0) Text('مدين ${_money((r['debit'] as num).toDouble())}'),
                if((r['credit'] as num).toDouble()>0) Text('دائن ${_money((r['credit'] as num).toDouble())}'),
              ]),
            ))),
          ],
        )),
    );
  }

  Widget _balanceCard(String label,double value)=>Card(child:ListTile(title:Text(label),trailing:Text(_money(value))));
  String _typeLabel(String type)=>switch(type){
    'receipt'=>'فاتورة توريد','payment'=>'دفعة للمورد','supplier_return'=>'مرتجع مورد',
    'opening_balance'=>'رصيد افتتاحي',_=>type};
}
