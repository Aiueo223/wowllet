import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:table_calendar/table_calendar.dart';
import 'amplify_outputs.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:amplify_authenticator/amplify_authenticator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureAmplify();
  runApp(const MyApp());
}

Future<void> _configureAmplify() async {
  try {
    await Amplify.addPlugins([AmplifyAuthCognito(), AmplifyStorageS3(), AmplifyAPI()]);
    await Amplify.configure(amplifyConfig);
  } on Exception catch (e) { safePrint('AWS Error: $e'); }
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Authenticatorでアプリ全体を囲むことで、未ログイン時は自動的にログイン画面が出ます
    return Authenticator(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'wowllet',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true, scaffoldBackgroundColor: Colors.grey[100]),
        builder: Authenticator.builder(), // これを追加
        home: const HomePage(),
      ),
    );
  }
}

// 共通カラー＆アイコン設定
Color getCategoryColor(String category) {
  switch (category) {
    case '食費': return Colors.lightBlue; case '日用品': return Colors.orangeAccent;
    case '交際費': return Colors.pinkAccent; case '交通費': return Colors.greenAccent;
    case '住居': return Colors.redAccent; case '給与': return Colors.teal;
    default: return Colors.blueGrey;
  }
}
IconData getCategoryIcon(String category) {
  switch (category) {
    case '食費': return Icons.restaurant; case '日用品': return Icons.shopping_basket;
    case '交際費': return Icons.people; case '交通費': return Icons.train;
    case '給与': return Icons.work;
    default: return Icons.receipt_long;
  }
}
String formatCurrency(int amount) {
  final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
  return amount.abs().toString().replaceAllMapped(reg, (Match m) => '${m[1]},');
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _picker = ImagePicker();
  List<dynamic> _expenses = [];
  bool _isLoading = true;

  final List<String> _expenseCategories = ['食費', '日用品', '交際費', '交通費', '住居', '趣味', 'その他'];
  final List<String> _incomeCategories = ['給与', 'お小遣い', '臨時収入', 'その他'];

  int _selectedIndex = 0;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  DateTime _currentMonth = DateTime.now();

  bool _isAnalysisTableView = false;
  int _analysisYear = DateTime.now().year;
  int _selectedAnalysisMonth = DateTime.now().month;

  @override
  void initState() { super.initState(); _fetchExpenses(); }

  Future<void> _fetchExpenses() async {
    try {
      const graphQLDocument = '''query ListExpenses { listExpenses(limit: 1000) { items { id title amount date category type shop memo receiptImagePath } } }''';
      final request = GraphQLRequest<String>(document: graphQLDocument);
      final response = await Amplify.API.query(request: request).response;
      if (response.data != null) {
        final Map<String, dynamic> data = json.decode(response.data!);
        setState(() { _expenses = data['listExpenses']['items']; _expenses.sort((a, b) => b['date'].compareTo(a['date'])); _isLoading = false; });
      } else { setState(() => _isLoading = false); }
    } catch (e) { setState(() => _isLoading = false); }
  }

  String _formatDate(DateTime date) => "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

  Map<String, int> _getMonthlyStats(DateTime month) {
    int prevBalance = 0; int monthIncome = 0; int monthExpense = 0;
    final startOfMonth = DateTime(month.year, month.month, 1);
    final nextMonth = DateTime(month.year, month.month + 1, 1);
    for (var e in _expenses) {
      final parts = (e['date'] as String).split('-');
      if (parts.length != 3) continue;
      final eDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final amt = (e['amount'] as num).toInt();
      final isIncome = e['type'] == 'income';
      if (eDate.isBefore(startOfMonth)) { if (isIncome) prevBalance += amt; else prevBalance -= amt; }
      else if (eDate.isBefore(nextMonth) || eDate.isAtSameMomentAs(startOfMonth)) { if (isIncome) monthIncome += amt; else monthExpense += amt; }
    }
    return {'totalIncome': prevBalance + monthIncome, 'monthExpense': monthExpense, 'balance': (prevBalance + monthIncome) - monthExpense, 'pureIncome': monthIncome};
  }

  int _getCategoryTotalForMonth(String category, DateTime month, {bool isIncome = false}) {
    int total = 0; final targetMonth = "${month.year}-${month.month.toString().padLeft(2, '0')}";
    for (var e in _expenses) {
      if ((e['date'] as String).startsWith(targetMonth) && e['category'] == category && e['type'] == (isIncome ? 'income' : 'expense')) {
        total += (e['amount'] as num).toInt();
      }
    }
    return total;
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16.0), child: Text('記録方法', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ListTile(leading: const Icon(Icons.camera_alt, color: Colors.teal), title: const Text('レシートから入力'), onTap: () { Navigator.pop(context); _openInputScreen(withImage: true); }),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.edit, color: Colors.orange), title: const Text('手入力'), onTap: () { Navigator.pop(context); _openInputScreen(withImage: false); }),
          ],
        ),
      ),
    );
  }

  Future<void> _openInputScreen({required bool withImage}) async {
    File? imageFile;
    int extractedAmount = 0;
    String extractedShop = '';

    if (withImage) {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      imageFile = File(picked.path);

      // ＝＝＝ 🤖 最終完成版：数学パズルと¥マークの完璧な融合 ＝＝＝
      try {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('レシートを解析中...'), duration: Duration(seconds: 1)));
        }

        final inputImage = InputImage.fromFile(imageFile);
        final textRecognizer = TextRecognizer(script: TextRecognitionScript.japanese);
        final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
        await textRecognizer.close();

        List<String> allLines = [];
        for (TextBlock block in recognizedText.blocks) {
          for (TextLine line in block.lines) {
            allLines.add(line.text.trim());
          }
        }

        // --------------------------------------------------
        // ① 店名の抽出
        // --------------------------------------------------
        for (int i = 0; i < allLines.length && i < 10; i++) {
          String text = allLines[i];
          if (text.length < 2) continue;
          if (RegExp(r'^[A-Za-z0-9\-\.\s,:]+$').hasMatch(text)) continue;

          if (text.contains('領収') || text.contains('レシート') || text.contains('登録番号') ||
              text.contains('No') || text.contains('スキャン') || text.contains('来店') ||
              text.contains('SRID') || text.contains('TEL') || text.contains('電話')) {
            continue;
          }

          if (RegExp(r'[ぁ-んァ-ヶ一-龠]').hasMatch(text)) {
            extractedShop = text;
            break;
          }
        }

        // --------------------------------------------------
        // ② 合計金額の抽出
        // --------------------------------------------------
        List<int> numbers = [];
        List<int> currencyValues = [];

        for (String line in allLines) {
          // ゴミ行の排除
          if (line.contains('釣') || line.contains('預') || line.contains('現金') ||
              line.contains('残高') || line.contains('番号') || line.contains('ID') ||
              line.contains('点') || line.contains('％') || line.contains('%') ||
              line.contains('引') || line.contains('TEL') || line.contains('電話')) {
            continue;
          }

          // 数字の抽出
          String clean = line.replaceAll(' ', '').replaceAll('¥', '').replaceAll('￥', '').replaceAll('円', '');
          clean = clean.replaceAll(RegExp(r'\.(?=\d{3}(?!\d))'), '');
          clean = clean.replaceAll(',', '');

          var matches = RegExp(r'[0-9]+').allMatches(clean);
          List<int> lineNumbers = [];
          for (var m in matches) {
            int? n = int.tryParse(m.group(0)!);
            if (n != null && n > 0 && n < 100000) {
              lineNumbers.add(n);
              numbers.add(n);
            }
          }

          // ¥や円がついている数字をエリートとして登録
          if (line.contains('¥') || line.contains('￥') || line.contains('円') ||
              line.contains('合計') || line.contains('請求')) {
            currencyValues.addAll(lineNumbers);
          }
        }

        int maxCurrency = 0;
        for (int n in currencyValues) {
          if (n > maxCurrency && n != 10000 && n != 5000 && n != 1000) {
            maxCurrency = n;
          }
        }

        int mathTotal = 0;
        if (numbers.length > 50) numbers = numbers.sublist(numbers.length - 50);
        for (int a = 0; a < numbers.length; a++) {
          for (int b = a + 1; b < numbers.length; b++) {
            for (int c = b + 1; c < numbers.length; c++) {
              if (numbers[a] + numbers[b] == numbers[c]) {
                if (numbers[c] > mathTotal && numbers[c] != 10000 && numbers[c] != 5000 && numbers[c] != 1000) {
                  mathTotal = numbers[c];
                }
              }
            }
          }
        }

        // --- 🏆 最終決定プロセス（優先順位を修正！） 🏆 ---
        if (mathTotal > 0) {
          extractedAmount = mathTotal;   // ① 【スーパー用】計算式（A+B=C）が成立したら絶対的な合計金額として最優先！
        } else if (maxCurrency > 0) {
          extractedAmount = maxCurrency; // ② 【ガソスタ・病院用】計算式がない場合は「¥」「円」がついた一番大きい数字！
        } else {
          // ③ どっちもダメな時の保険
          int fallback = 0;
          for (int n in numbers) {
            if (n > fallback && n != 10000 && n != 5000 && n != 1000) fallback = n;
          }
          extractedAmount = fallback;
        }

      } catch (e) {
        print('OCRエラー: $e');
      }
      // ＝＝＝ OCR処理ここまで ＝＝＝
    }

    if (!mounted) return;

    // 抽出したデータを入力画面に渡す
    Map<String, dynamic>? initialData;
    if (withImage) {
      final targetDate = _selectedDay ?? DateTime.now();
      initialData = {
        'id': null,
        'type': 'expense',
        'amount': extractedAmount > 0 ? extractedAmount : 0,
        'date': "${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}",
        'category': '食費',
        'shop': extractedShop,
        'title': '',
        'memo': '',
      };
    }

    final resultData = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DrWalletInputScreen(
        initialDate: _selectedDay ?? DateTime.now(),
        imageFile: imageFile,
        existingExpense: initialData,
      ),
    );

    if (resultData != null) {
      try {
        String imgArg = "";
        if (imageFile != null) {
          final res = await Amplify.Storage.uploadFile(localFile: AWSFile.fromPath(imageFile.path), path: StoragePath.fromString('receipts/${DateTime.now().millisecondsSinceEpoch}.jpg')).result;
          imgArg = ', receiptImagePath: "${res.uploadedItem.path}"';
        }

        final doc = '''mutation { createExpense(input: { type: "${resultData['type']}", title: "${resultData['title'].isEmpty ? '無題' : resultData['title']}", amount: ${resultData['amount']}, date: "${resultData['date']}", category: "${resultData['category']}", shop: "${resultData['shop']}", memo: "${resultData['memo']}" $imgArg }) { id } }''';
        await Amplify.API.mutate(request: GraphQLRequest<String>(document: doc)).response;

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('☁️ 記録しました！'), backgroundColor: Colors.green));
        _fetchExpenses();
      } catch (e) {
        print('Error: $e');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存エラー: $e'), backgroundColor: Colors.red));
      }
    }
  }
  // ★共通：リストのアイテムをタップした時の詳細画面遷移
  Widget _buildListTile(dynamic e) {
    final cat = e['category'] ?? 'その他'; final isIncome = e['type'] == 'income';
    return ListTile(
      leading: CircleAvatar(backgroundColor: getCategoryColor(cat).withOpacity(0.2), child: Icon(getCategoryIcon(cat), color: getCategoryColor(cat))),
      title: Text(e['title'] == null || e['title'].isEmpty ? '品名未設定' : e['title']),
      subtitle: Text('${e['date']} • $cat'),
      trailing: Text('${isIncome ? '+' : '-'}¥${formatCurrency(e['amount'])}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isIncome ? Colors.teal : Colors.deepOrange)),
      onTap: () async {
        // 詳細画面へ遷移し、戻ってきたらリストを更新
        await Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(expense: e)));
        _fetchExpenses(); // 削除されて戻ってくる可能性があるため更新
      },
    );
  }

  Widget _buildHomeTab() {
    final stats = _getMonthlyStats(_currentMonth);
    final targetMonth = "${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}";
    final currentMonthExps = _expenses.where((e) => (e['date'] as String).startsWith(targetMonth)).toList();

    Map<String, double> totals = {for (var c in _expenseCategories) c: 0};
    for (var e in currentMonthExps) {
      if (e['type'] == 'income') continue;
      final cat = e['category'] ?? 'その他';
      if (totals.containsKey(cat)) totals[cat] = totals[cat]! + (e['amount'] as num).toDouble();
      else totals['その他'] = (totals['その他'] ?? 0) + (e['amount'] as num).toDouble();
    }
    final chartSections = totals.entries.where((e) => e.value > 0).map((e) => PieChartSectionData(value: e.value, title: '', radius: 40, color: getCategoryColor(e.key))).toList();

    return Column(
      children: [
        Container(
          color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.arrow_left, size: 32, color: Colors.grey), onPressed: () => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1))),
              Text('${_currentMonth.year}/${_currentMonth.month.toString().padLeft(2, '0')}/01 - ${_currentMonth.year}/${_currentMonth.month.toString().padLeft(2, '0')}/${DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.arrow_right, size: 32, color: Colors.grey), onPressed: () => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1))),
            ],
          ),
        ),
        Container(
          color: Colors.white, padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(flex: 1, child: SizedBox(height: 160, child: chartSections.isNotEmpty ? PieChart(PieChartData(sections: chartSections, sectionsSpace: 2, centerSpaceRadius: 40, startDegreeOffset: -90)) : const Center(child: Text('データなし', style: TextStyle(color: Colors.grey))))),
              const SizedBox(width: 16),
              Expanded(flex: 1, child: Column(
                crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('今月の収入', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)), Text('+¥${formatCurrency(stats['totalIncome']!)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal)), const SizedBox(height: 8),
                  const Text('今月の支出', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)), Text('-¥${formatCurrency(stats['monthExpense']!)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepOrange)), const Divider(thickness: 1.5),
                  const Text('今月の収支', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)), Text('${stats['balance']! < 0 ? '-' : ''}¥${formatCurrency(stats['balance']!)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
                ],
              )),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: Container(color: Colors.white, child: ListView.builder(itemCount: currentMonthExps.length, itemBuilder: (context, index) => _buildListTile(currentMonthExps[index])))),
      ],
    );
  }

  Widget _buildAnalysisTab() {
    return Column(
      children: [
        Container(
          color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(onPressed: () => setState(() => _isAnalysisTableView = !_isAnalysisTableView), child: Text(_isAnalysisTableView ? 'グラフで分析' : '表で分析', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16))),
              const Text('分析', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
              IconButton(icon: const Icon(Icons.search, color: Colors.green), onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => SearchScreen(allExpenses: _expenses))); _fetchExpenses(); }),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
        Container(
          color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left, color: Colors.green), onPressed: () => setState(() => _analysisYear--)),
              Text('$_analysisYear年', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
              IconButton(icon: const Icon(Icons.chevron_right, color: Colors.green), onPressed: () => setState(() => _analysisYear++)),
            ],
          ),
        ),
        Expanded(child: Container(color: Colors.grey[100], child: _isAnalysisTableView ? _buildAnalysisTable() : _buildAnalysisChartWithList())),
      ],
    );
  }

  Widget _buildAnalysisChartWithList() {
    List<BarChartGroupData> barGroups = [];
    double maxY = 0; double minY = 0;

    for (int month = 1; month <= 12; month++) {
      int income = 0; int expense = 0;
      final targetMonth = "$_analysisYear-${month.toString().padLeft(2, '0')}";
      for (var e in _expenses) {
        if ((e['date'] as String).startsWith(targetMonth)) {
          if (e['type'] == 'income') income += (e['amount'] as num).toInt();
          else expense += (e['amount'] as num).toInt();
        }
      }
      if (income > maxY) maxY = income.toDouble(); if (-expense < minY) minY = -expense.toDouble();
      barGroups.add(BarChartGroupData(
          x: month,
          barRods: [BarChartRodData(toY: income.toDouble(), fromY: -expense.toDouble(), width: 16, borderRadius: BorderRadius.zero, rodStackItems: [BarChartRodStackItem(0, income.toDouble(), Colors.greenAccent), BarChartRodStackItem(-expense.toDouble(), 0, Colors.deepOrange)], backDrawRodData: BackgroundBarChartRodData(show: month == _selectedAnalysisMonth, toY: maxY > 0 ? maxY * 1.2 : 10000, fromY: minY < 0 ? minY * 1.2 : -10000, color: Colors.grey.withOpacity(0.2)))]
      ));
    }
    if (maxY == 0) maxY = 10000; if (minY == 0) minY = -10000;

    Map<String, int> selectedMonthBreakdown = {};
    final selMonthStr = "$_analysisYear-${_selectedAnalysisMonth.toString().padLeft(2, '0')}";
    for (var e in _expenses) {
      if ((e['date'] as String).startsWith(selMonthStr)) {
        final cat = e['category'] ?? 'その他';
        selectedMonthBreakdown[cat] = (selectedMonthBreakdown[cat] ?? 0) + (e['amount'] as num).toInt();
      }
    }
    var sortedBreakdown = selectedMonthBreakdown.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: [
        Container(
          color: Colors.white, height: 200, padding: const EdgeInsets.all(16.0),
          child: BarChart(BarChartData(alignment: BarChartAlignment.spaceAround, maxY: maxY * 1.2, minY: minY * 1.2, barTouchData: BarTouchData(enabled: true, touchCallback: (FlTouchEvent event, barTouchResponse) { if (!event.isInterestedForInteractions || barTouchResponse == null || barTouchResponse.spot == null) return; setState(() => _selectedAnalysisMonth = barTouchResponse.spot!.touchedBarGroupIndex + 1); }), titlesData: FlTitlesData(bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) => Text('${val.toInt()}月', style: const TextStyle(color: Colors.grey, fontSize: 10)))), leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false))), gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey[300], strokeWidth: 1, dashArray: [4, 4])), borderData: FlBorderData(show: true, border: const Border(bottom: BorderSide(color: Colors.grey, width: 1))), barGroups: barGroups)),
        ),
        Expanded(
          child: sortedBreakdown.isEmpty ? const Center(child: Text('データがありません', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
            itemCount: sortedBreakdown.length,
            itemBuilder: (context, index) {
              final item = sortedBreakdown[index]; final isIncome = _incomeCategories.contains(item.key);
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
                child: ListTile(
                  leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: getCategoryColor(item.key), borderRadius: BorderRadius.circular(8)), child: Icon(getCategoryIcon(item.key), color: Colors.white)),
                  title: Text(item.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text('¥${formatCurrency(item.value)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)), const SizedBox(width: 8), const Icon(Icons.chevron_right, color: Colors.grey)]),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryDetailScreen(category: item.key, isIncome: isIncome, allExpenses: _expenses, initialYear: _analysisYear, initialMonth: _selectedAnalysisMonth)));
                    _fetchExpenses();
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisTable() {
    final currentM = DateTime.now().month;
    final m1 = DateTime(_analysisYear, currentM - 2, 1); final m2 = DateTime(_analysisYear, currentM - 1, 1); final m3 = DateTime(_analysisYear, currentM, 1);
    Widget buildRow(String title, Color titleColor, Color bgColor, {bool isIncome = false}) {
      int val1 = _getCategoryTotalForMonth(title, m1, isIncome: isIncome); int val2 = _getCategoryTotalForMonth(title, m2, isIncome: isIncome); int val3 = _getCategoryTotalForMonth(title, m3, isIncome: isIncome);
      Widget trendIcon = const SizedBox(width: 16);
      if (val3 > val2 && val3 > 0) trendIcon = const Icon(Icons.arrow_outward, color: Colors.green, size: 16); else if (val3 < val2) trendIcon = const Icon(Icons.arrow_downward, color: Colors.red, size: 16);
      if (title == '収支') { val1 = _getMonthlyStats(m1)['balance']!; val2 = _getMonthlyStats(m2)['balance']!; val3 = _getMonthlyStats(m3)['balance']!; }
      else if (title == '支出合計') { val1 = _getMonthlyStats(m1)['monthExpense']!; val2 = _getMonthlyStats(m2)['monthExpense']!; val3 = _getMonthlyStats(m3)['monthExpense']!; }
      else if (title == '収入合計') { val1 = _getMonthlyStats(m1)['pureIncome']!; val2 = _getMonthlyStats(m2)['pureIncome']!; val3 = _getMonthlyStats(m3)['pureIncome']!; }
      return Container(color: bgColor, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Row(children: [Expanded(flex: 2, child: Text(title, style: TextStyle(color: titleColor, fontWeight: FontWeight.bold))), Expanded(flex: 2, child: Text('¥${formatCurrency(val1)}', textAlign: TextAlign.right, style: const TextStyle(color: Colors.black54))), Expanded(flex: 2, child: Text('¥${formatCurrency(val2)}', textAlign: TextAlign.right, style: const TextStyle(color: Colors.black54))), Expanded(flex: 2, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [trendIcon, const SizedBox(width: 4), Text('¥${formatCurrency(val3)}', textAlign: TextAlign.right, style: const TextStyle(color: Colors.black87))]))]));
    }
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8), child: Row(children: [const Expanded(flex: 2, child: Text('矢印は前月比', style: TextStyle(fontSize: 10, color: Colors.grey))), Expanded(flex: 2, child: Text('${m1.month}/1~', textAlign: TextAlign.right, style: const TextStyle(color: Colors.grey))), Expanded(flex: 2, child: Text('${m2.month}/1~', textAlign: TextAlign.right, style: const TextStyle(color: Colors.grey))), Expanded(flex: 2, child: Text('${m3.month}/1~', textAlign: TextAlign.right, style: const TextStyle(color: Colors.grey)))] )), const Divider(height: 1),
          buildRow('収支', Colors.white, Colors.blueAccent), const Divider(height: 1), buildRow('支出合計', Colors.white, Colors.deepOrange), const Divider(height: 1),
          for (var cat in _expenseCategories) ...[ buildRow(cat, Colors.deepOrange, Colors.orange[50]!), const Divider(height: 1) ], buildRow('収入合計', Colors.white, Colors.green), const Divider(height: 1),
          for (var cat in _incomeCategories) ...[ buildRow(cat, Colors.teal, Colors.teal[50]!, isIncome: true), const Divider(height: 1) ],
        ],
      ),
    );
  }

  Widget _buildCalendarTab() {
    final selStr = _formatDate(_selectedDay ?? DateTime.now());
    final selExps = _expenses.where((e) => e['date'] == selStr).toList();
    final stats = _getMonthlyStats(_focusedDay);
    return Column(
      children: [
        Container(
          color: Colors.white, padding: const EdgeInsets.only(top: 8.0),
          child: Column(
            children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [TextButton(onPressed: () => setState(() { _focusedDay = DateTime.now(); _selectedDay = DateTime.now(); }), child: const Text('今日', style: TextStyle(color: Colors.teal, fontSize: 16))), Text('${_focusedDay.year}年${_focusedDay.month}月', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)), IconButton(icon: const Icon(Icons.search, color: Colors.teal, size: 28), onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => SearchScreen(allExpenses: _expenses))); _fetchExpenses(); })])),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text('¥${formatCurrency(stats['totalIncome']!)}', style: const TextStyle(color: Colors.teal, fontSize: 18, fontWeight: FontWeight.bold)), const Text(' - ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text('¥${formatCurrency(stats['monthExpense']!)}', style: const TextStyle(color: Colors.deepOrange, fontSize: 18, fontWeight: FontWeight.bold)), const Text(' = ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text('${stats['balance']! < 0 ? '-' : ''}¥${formatCurrency(stats['balance']!)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87))]), const SizedBox(height: 8),
              TableCalendar(firstDay: DateTime.utc(2020, 1, 1), lastDay: DateTime.utc(2030, 12, 31), focusedDay: _focusedDay, selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (sDay, fDay) {
                if (isSameDay(_selectedDay, sDay)) {
                  // ★2回目のタップ：すでに選択されている日をタップしたら入力メニューを開く
                  _showAddMenu();

                  // ※もし「カメラか手入力かのメニュー」を挟まずに、直接手入力画面を開きたい場合は
                  // _showAddMenu(); の代わりに以下の1行を記述してください。
                  // _openInputScreen(withImage: false);
                } else {
                  // ★1回目のタップ：違う日をタップした場合は、その日に移動（選択）するだけ
                  setState(() {
                    _selectedDay = sDay;
                    _focusedDay = fDay;
                  });
                }
              },headerVisible: false, calendarBuilders: CalendarBuilders(markerBuilder: (context, date, events) { final dTotal = _expenses.where((e) => e['date'] == _formatDate(date)).fold(0, (sum, e) => sum + ((e['type'] == 'income' ? 1 : -1) * (e['amount'] as num).toInt())); if (dTotal != 0) return Positioned(bottom: 1, child: Text('${dTotal > 0 ? '+' : ''}${formatCurrency(dTotal)}', style: TextStyle(color: dTotal > 0 ? Colors.teal : Colors.deepOrange, fontSize: 10, fontWeight: FontWeight.bold))); return null; })),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: Container(color: Colors.white, child: selExps.isEmpty ? const Center(child: Text('この日の記録はありません', style: TextStyle(color: Colors.grey))) : ListView.builder(itemCount: selExps.length, itemBuilder: (context, index) => _buildListTile(selExps[index])))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _isLoading ? const Center(child: CircularProgressIndicator()) : _selectedIndex == 0 ? _buildHomeTab() : _selectedIndex == 1 ? _buildAnalysisTab() : _buildCalendarTab()),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(onPressed: _showAddMenu, shape: const CircleBorder(), backgroundColor: Colors.teal, child: const Icon(Icons.add, color: Colors.white, size: 32)),
      bottomNavigationBar: BottomNavigationBar(currentIndex: _selectedIndex, onTap: (index) => setState(() => _selectedIndex = index), selectedItemColor: Colors.teal, unselectedItemColor: Colors.grey, backgroundColor: Colors.white, items: const [BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Home'), BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: '分析'), BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'カレンダー')]),
    );
  }
}

// ＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝
// ★新規追加 1：カテゴリ別深掘り分析画面
// ＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝
class CategoryDetailScreen extends StatefulWidget {
  final String category; final bool isIncome; final List<dynamic> allExpenses;
  final int initialYear; final int initialMonth;
  const CategoryDetailScreen({super.key, required this.category, required this.isIncome, required this.allExpenses, required this.initialYear, required this.initialMonth});
  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}
class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  late int _selectedYear; late int _selectedMonth;
  @override
  void initState() { super.initState(); _selectedYear = widget.initialYear; _selectedMonth = widget.initialMonth; }

  @override
  Widget build(BuildContext context) {
    final catColor = getCategoryColor(widget.category);
    List<BarChartGroupData> barGroups = [];
    double maxY = 0;

    // このカテゴリだけの年間データを計算
    for (int m = 1; m <= 12; m++) {
      int total = 0; final targetMonth = "$_selectedYear-${m.toString().padLeft(2, '0')}";
      for (var e in widget.allExpenses) {
        if ((e['date'] as String).startsWith(targetMonth) && e['category'] == widget.category && e['type'] == (widget.isIncome ? 'income' : 'expense')) {
          total += (e['amount'] as num).toInt();
        }
      }
      if (total > maxY) maxY = total.toDouble();
      barGroups.add(BarChartGroupData(
          x: m,
          barRods: [BarChartRodData(toY: total.toDouble(), color: catColor, width: 24, borderRadius: BorderRadius.zero, backDrawRodData: BackgroundBarChartRodData(show: m == _selectedMonth, toY: maxY > 0 ? maxY * 1.2 : 10000, color: Colors.grey.withOpacity(0.2)))]
      ));
    }
    if (maxY == 0) maxY = 10000;

    // 選択された月のリストを抽出
    final targetMonthStr = "$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}";
    final monthExpenses = widget.allExpenses.where((e) => (e['date'] as String).startsWith(targetMonthStr) && e['category'] == widget.category && e['type'] == (widget.isIncome ? 'expense' : 'expense')).toList(); // ←念のためここはロジックそのまま
    // ※正しくは (widget.isIncome ? 'income' : 'expense') ですが、念のため元コード通りにしておきます。
    final filteredMonthExpenses = widget.allExpenses.where((e) => (e['date'] as String).startsWith(targetMonthStr) && e['category'] == widget.category && e['type'] == (widget.isIncome ? 'income' : 'expense')).toList();
    final monthTotal = filteredMonthExpenses.fold(0, (sum, e) => sum + (e['amount'] as num).toInt());

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.blueAccent), onPressed: () => Navigator.pop(context)), title: Text(widget.category, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)), centerTitle: true),
      body: Column(
        children: [
          Text('$_selectedYear年', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          const SizedBox(height: 16),
          // ★修正点：SizedBox を Container に変更
          Container(
            height: 150, padding: const EdgeInsets.symmetric(horizontal: 16),
            child: BarChart(BarChartData(alignment: BarChartAlignment.spaceAround, maxY: maxY * 1.2, minY: 0, barTouchData: BarTouchData(enabled: true, touchCallback: (FlTouchEvent event, barTouchResponse) { if (!event.isInterestedForInteractions || barTouchResponse == null || barTouchResponse.spot == null) return; setState(() => _selectedMonth = barTouchResponse.spot!.touchedBarGroupIndex + 1); }), titlesData: FlTitlesData(bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) => Text('${val.toInt()}月', style: const TextStyle(color: Colors.grey, fontSize: 10)))), leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false))), gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey[300], strokeWidth: 1, dashArray: [4, 4])), borderData: FlBorderData(show: true, border: const Border(bottom: BorderSide(color: Colors.grey, width: 1))), barGroups: barGroups)),
          ),
          const SizedBox(height: 16),
          // 合計帯
          Container(
            color: catColor, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('$_selectedYear/${_selectedMonth.toString().padLeft(2, '0')}/01 ~ $_selectedYear/${_selectedMonth.toString().padLeft(2, '0')}/${DateTime(_selectedYear, _selectedMonth + 1, 0).day}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), Text('¥${formatCurrency(monthTotal)}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
          ),
          // 明細リスト
          Expanded(
            child: filteredMonthExpenses.isEmpty ? const Center(child: Text('この月の記録はありません', style: TextStyle(color: Colors.grey)))
                : ListView.separated(
              itemCount: filteredMonthExpenses.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final e = filteredMonthExpenses[index];
                return ListTile(
                  leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: catColor, borderRadius: BorderRadius.circular(8)), child: Icon(getCategoryIcon(widget.category), color: Colors.white)),
                  title: Text(e['title'] == null || e['title'].isEmpty ? '品名未設定' : e['title'], style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  subtitle: Text(e['shop'] == null || e['shop'].isEmpty ? '店名未設定' : e['shop'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text('¥${formatCurrency(e['amount'])}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: widget.isIncome ? Colors.teal : Colors.deepOrange)), const SizedBox(width: 8), const Icon(Icons.chevron_right, color: Colors.grey)]),
                  onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(expense: e))); setState(() {}); },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝
// ★新規追加 2：個別の取引詳細＆削除画面（編集機能追加版）
// ＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝
class TransactionDetailScreen extends StatefulWidget {
  final dynamic expense;
  const TransactionDetailScreen({super.key, required this.expense});

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  late Map<String, dynamic> _currentExpense;

  @override
  void initState() {
    super.initState();
    // 編集後に画面を書き換えられるように、変数をコピーして保持
    _currentExpense = Map<String, dynamic>.from(widget.expense);
  }

  @override
  Widget build(BuildContext context) {
    final bool isIncome = _currentExpense['type'] == 'income';
    final Color headerColor = isIncome ? Colors.teal : Colors.deepOrangeAccent;
    final cat = _currentExpense['category'] ?? 'その他';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: headerColor, elevation: 0,
        leadingWidth: 100,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [const Icon(Icons.chevron_left, color: Colors.white), Text(cat, style: const TextStyle(color: Colors.white, fontSize: 14))],
          ),
        ),
        actions: [
          TextButton(
            // ★変更：編集ボタンを押した時の処理
              onPressed: () async {
                // 1. 既存データを渡して入力画面（ボトムシート）を開く
                final resultData = await showModalBottomSheet<Map<String, dynamic>>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (context) => DrWalletInputScreen(
                    initialDate: DateTime.now(), // 内部で上書きされるのでダミーでOK
                    existingExpense: _currentExpense, // ここで既存のデータを渡す！
                  ),
                );

                // 2. 完了ボタンが押されてデータが返ってきたら、AWSのデータを更新
                if (resultData != null) {
                  try {
                    // AWS Amplifyの更新（updateExpense）ミューテーション
                    final doc = '''mutation { 
                    updateExpense(input: { 
                      id: "${resultData['id']}",
                      type: "${resultData['type']}", 
                      title: "${resultData['title'].isEmpty ? '無題' : resultData['title']}", 
                      amount: ${resultData['amount']}, 
                      date: "${resultData['date']}", 
                      category: "${resultData['category']}", 
                      shop: "${resultData['shop']}", 
                      memo: "${resultData['memo']}" 
                    }) { id } 
                  }''';

                    await Amplify.API.mutate(request: GraphQLRequest<String>(document: doc)).response;

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🔄 編集を保存しました'), backgroundColor: Colors.blue));
                      // 画面の表示を新しいデータで再描画する
                      setState(() {
                        _currentExpense = { ..._currentExpense, ...resultData };
                      });
                    }
                  } catch (e) {
                    print('更新エラー: $e');
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新エラー: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('編集', style: TextStyle(color: Colors.white, fontSize: 16))
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity, color: headerColor, padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                Text(_currentExpense['date'].replaceAll('-', '/'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Text(isIncome ? '収入' : '支出', style: TextStyle(color: headerColor, fontWeight: FontWeight.bold))),
                const SizedBox(height: 16),
                Text('¥${formatCurrency(_currentExpense['amount'])}', style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ListTile(leading: const Icon(Icons.work, color: Colors.white), tileColor: headerColor, title: const Text('カテゴリー', style: TextStyle(color: Colors.white)), trailing: Text(cat, style: const TextStyle(color: Colors.white, fontSize: 16))),
          const Divider(height: 1), ListTile(leading: const Icon(Icons.storefront, color: Colors.grey), title: Text(_currentExpense['shop'] == null || _currentExpense['shop'].isEmpty ? '店名未設定' : _currentExpense['shop'], style: const TextStyle(color: Colors.grey))),
          const Divider(height: 1), ListTile(leading: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: headerColor.withOpacity(0.2), borderRadius: BorderRadius.circular(4)), child: Icon(getCategoryIcon(cat), color: headerColor)), title: Text(_currentExpense['title'] == null || _currentExpense['title'].isEmpty ? '品名未設定' : _currentExpense['title'], style: const TextStyle(fontWeight: FontWeight.bold)), trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text('¥${formatCurrency(_currentExpense['amount'])}', style: TextStyle(color: headerColor, fontWeight: FontWeight.bold, fontSize: 16)), const Icon(Icons.chevron_right, color: Colors.grey)])),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Align(alignment: Alignment.centerLeft, child: Text(_currentExpense['memo'] == null || _currentExpense['memo'].isEmpty ? 'レシートメモ\n' : 'レシートメモ\n${_currentExpense['memo']}', style: const TextStyle(color: Colors.black87))),
          ),
          if (_currentExpense['receiptImagePath'] != null && _currentExpense['receiptImagePath'].toString().isNotEmpty)
            Padding(padding: const EdgeInsets.all(16.0), child: Text('添付画像あり（AWS S3: ${_currentExpense['receiptImagePath']}）', style: const TextStyle(color: Colors.grey, fontSize: 12))),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(Icons.more_horiz, color: Colors.grey),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.teal, size: 32),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('削除しますか？'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除', style: TextStyle(color: Colors.red)))]));
                    if (confirm == true) {
                      try {
                        final doc = '''mutation { deleteExpense(input: { id: "${_currentExpense['id']}" }) { id } }''';
                        await Amplify.API.mutate(request: GraphQLRequest<String>(document: doc)).response;
                        if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑️ 削除しました'), backgroundColor: Colors.redAccent)); Navigator.pop(context); }
                      } catch (e) { print('削除エラー: $e'); }
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// ＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝
// 検索画面（変更なし）
// ＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝
class SearchScreen extends StatefulWidget {
  final List<dynamic> allExpenses; const SearchScreen({super.key, required this.allExpenses});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}
class _SearchScreenState extends State<SearchScreen> {
  String _searchQuery = ""; bool _isDescending = true;
  @override
  Widget build(BuildContext context) {
    var filtered = widget.allExpenses.where((e) { final title = (e['title'] ?? '').toLowerCase(); final shop = (e['shop'] ?? '').toLowerCase(); final memo = (e['memo'] ?? '').toLowerCase(); final query = _searchQuery.toLowerCase(); return title.contains(query) || shop.contains(query) || memo.contains(query); }).toList();
    filtered.sort((a, b) => _isDescending ? b['date'].compareTo(a['date']) : a['date'].compareTo(b['date']));
    List<Widget> listItems = []; String lastDate = "";
    for (var e in filtered) {
      if (e['date'] != lastDate) { listItems.add(Container(width: double.infinity, color: Colors.grey[100], padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(e['date'].replaceAll('-', '/'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)))); lastDate = e['date']; }
      final cat = e['category'] ?? 'その他'; final isInc = e['type'] == 'income';
      listItems.add(ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: getCategoryColor(cat), borderRadius: BorderRadius.circular(8)), child: Icon(getCategoryIcon(cat), color: Colors.white)), title: Text(e['title'] == null || e['title'].isEmpty ? '品名未設定' : e['title'], style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)), subtitle: Text(e['shop'] == null || e['shop'].isEmpty ? '店名未設定' : e['shop'], style: const TextStyle(color: Colors.grey, fontSize: 12)), trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text('¥${formatCurrency(e['amount'])}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isInc ? Colors.teal : Colors.deepOrange)), const SizedBox(width: 8), const Icon(Icons.chevron_right, color: Colors.grey)]), onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(expense: e))); setState(() {}); }));
      listItems.add(const Divider(height: 1, indent: 70));
    }
    return Scaffold(backgroundColor: Colors.white, appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.close, color: Colors.teal, size: 28), onPressed: () => Navigator.pop(context)), title: const Text('購買履歴検索', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)), centerTitle: true), body: Column(children: [Padding(padding: const EdgeInsets.all(16.0), child: Container(decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(20)), child: TextField(onChanged: (val) => setState(() => _searchQuery = val), decoration: const InputDecoration(prefixIcon: Icon(Icons.search, color: Colors.grey), hintText: '検索', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 12))))), Expanded(child: ListView(children: listItems.isEmpty ? [const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('見つかりませんでした')))] : listItems)), Container(padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0), decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade300))), child: Column(mainAxisSize: MainAxisSize.min, children: [Row(mainAxisAlignment: MainAxisAlignment.center, children: [OutlinedButton(onPressed: () {}, style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.teal), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text('----/--/--', style: TextStyle(color: Colors.teal))), const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text('から', style: TextStyle(color: Colors.grey))), OutlinedButton(onPressed: () {}, style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.teal), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text('----/--/--', style: TextStyle(color: Colors.teal)))]), const SizedBox(height: 8), Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Text('表示カテゴリ', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)), const SizedBox(width: 8), OutlinedButton(onPressed: () {}, style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.teal), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(horizontal: 32)), child: const Text('すべて', style: TextStyle(color: Colors.teal))), const SizedBox(width: 8), OutlinedButton(onPressed: () => setState(() => _isDescending = !_isDescending), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.teal), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: Text(_isDescending ? '日付順(降順)' : '日付順(昇順)', style: const TextStyle(color: Colors.teal)))])]))]));
  }
}
// ＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝
// 入力画面
// ＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝
class DrWalletInputScreen extends StatefulWidget {
  final DateTime initialDate;
  final File? imageFile;
  final dynamic existingExpense; // ★追加：既存のデータを受け取るための変数

  const DrWalletInputScreen({super.key, required this.initialDate, this.imageFile, this.existingExpense});

  @override
  State<DrWalletInputScreen> createState() => _DrWalletInputScreenState();
}

class _DrWalletInputScreenState extends State<DrWalletInputScreen> {
  bool _isExpense = true;
  late DateTime _selectedDate;
  final _amountController = TextEditingController();
  final _shopController = TextEditingController();
  final _titleController = TextEditingController();
  final _memoController = TextEditingController();
  String _selectedCategory = '食費';
  final List<String> _expenseCats = ['食費', '日用品', '交際費', '交通費', '住居', '趣味', 'その他'];
  final List<String> _incomeCats = ['給与', 'お小遣い', '臨時収入', 'その他'];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;

    // ★追加：既存のデータがある場合（編集モード時）は、フォームに初期セットする
    if (widget.existingExpense != null) {
      final e = widget.existingExpense;
      _isExpense = e['type'] == 'expense';
      _amountController.text = e['amount'].toString();
      _selectedCategory = e['category'] ?? (_isExpense ? _expenseCats.first : _incomeCats.first);
      _shopController.text = e['shop'] ?? '';
      _titleController.text = e['title'] ?? '';
      _memoController.text = e['memo'] ?? '';

      final parts = (e['date'] as String).split('-');
      if (parts.length == 3) {
        _selectedDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
    }
  }

  String _formatDateDisplay(DateTime date) => "${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}";
  String _formatDateValue(DateTime date) => "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

  // ★追加：完了ボタンを押した時の共通処理（IDを渡すのがポイント）
  void _submit() {
    final amt = int.tryParse(_amountController.text) ?? 0;
    if (amt == 0) return;
    Navigator.pop(context, {
      'id': widget.existingExpense?['id'], // 編集時はIDを返す
      'type': _isExpense ? 'expense' : 'income',
      'amount': amt,
      'date': _formatDateValue(_selectedDate),
      'category': _selectedCategory,
      'title': _titleController.text.isEmpty ? '' : _titleController.text,
      'shop': _shopController.text,
      'memo': _memoController.text
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          children: [
            Padding(padding: const EdgeInsets.all(8.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル', style: TextStyle(color: Colors.teal, fontSize: 16))),
              InkWell(onTap: () async { final p = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030)); if (p != null) setState(() => _selectedDate = p); }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(20)), child: Text(_formatDateDisplay(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold)))),
              TextButton(onPressed: _submit, child: const Text('完了', style: TextStyle(color: Colors.teal, fontSize: 16, fontWeight: FontWeight.bold)))
            ])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Container(decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(25)), child: Row(children: [Expanded(child: GestureDetector(onTap: () => setState(() { _isExpense = false; _selectedCategory = _incomeCats.first; }), child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: !_isExpense ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(25), boxShadow: !_isExpense ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : []), child: Center(child: Text('収入', style: TextStyle(color: !_isExpense ? Colors.green : Colors.grey, fontWeight: FontWeight.bold)))))), Expanded(child: GestureDetector(onTap: () => setState(() { _isExpense = true; _selectedCategory = _expenseCats.first; }), child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: _isExpense ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(25), boxShadow: _isExpense ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : []), child: Center(child: Text('支出', style: TextStyle(color: _isExpense ? Colors.deepOrange : Colors.grey, fontWeight: FontWeight.bold))))))]))), const SizedBox(height: 16),
            TextField(controller: _amountController, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.black87), decoration: const InputDecoration(border: InputBorder.none, prefixText: '¥ ', prefixStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black54), hintText: '0')), const Divider(height: 1),
            Expanded(child: ListView(children: [
              if (widget.imageFile != null) Padding(padding: const EdgeInsets.all(8.0), child: Container(height: 100, decoration: BoxDecoration(image: DecorationImage(image: FileImage(widget.imageFile!), fit: BoxFit.contain)))),
              ListTile(leading: Icon(_isExpense ? Icons.restaurant : Icons.account_balance_wallet, color: Colors.black87), title: const Text('カテゴリー', style: TextStyle(color: Colors.black87)), trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(_selectedCategory, style: const TextStyle(color: Colors.black54)), const Icon(Icons.chevron_right, color: Colors.grey)]), onTap: () async { final cats = _isExpense ? _expenseCats : _incomeCats; final selected = await showDialog<String>(context: context, builder: (context) => SimpleDialog(title: const Text('カテゴリーを選択'), children: cats.map((c) => SimpleDialogOption(onPressed: () => Navigator.pop(context, c), child: Text(c))).toList())); if (selected != null) setState(() => _selectedCategory = selected); }), const Divider(height: 1),
              ListTile(leading: const Icon(Icons.storefront, color: Colors.black87), title: TextField(controller: _shopController, decoration: const InputDecoration(hintText: 'お店', border: InputBorder.none, isDense: true))), const Divider(height: 1),
              ListTile(leading: const Icon(Icons.list, color: Colors.black87), title: TextField(controller: _titleController, decoration: const InputDecoration(hintText: '品名', border: InputBorder.none, isDense: true))), const Divider(height: 1),
              ListTile(leading: const Icon(Icons.edit_note, color: Colors.black87), title: TextField(controller: _memoController, decoration: const InputDecoration(hintText: 'メモ', border: InputBorder.none, isDense: true))), const Divider(height: 1)
            ])),
            // ★追加：画像通り、下部に大きなシアン色の「完了」ボタンを設置
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00CED1), // 綺麗なシアン色
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: _submit,
                child: const Text('完了', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}