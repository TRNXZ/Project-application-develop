// เกมงู (Snake) สำหรับ dartpad.dev (เลือกโหมด Flutter)
//
// องค์ความรู้ที่ใช้:
//  1) Queue    -> ตัวงูคือ Queue: หัวเข้าท้าย (addLast) / หางออกหน้า (removeFirst)
//                 และใช้ Queue เป็น input buffer เก็บคำสั่งเลี้ยวที่กดรัว ๆ
//  2) Hash Set -> เก็บตำแหน่งตัวงู/สิ่งกีดขวางเพื่อเช็กการชนใน O(1)
//                 และหาช่องว่างสำหรับวางอาหาร
//  3) Sorting  -> จัดอันดับคะแนนสูงสุด 5 อันดับ
//
// กติกา: กินอาหารได้ 1 คะแนน, ทุก ๆ 5 คะแนนจะมีสิ่งกีดขวางโผล่เพิ่ม,
// ยิ่งคะแนนสูงงูยิ่งเร็ว, ชนกำแพง/ตัวเอง/สิ่งกีดขวาง = จบเกม

import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const SnakeApp());

class SnakeApp extends StatelessWidget {
  const SnakeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Snake Queue',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
        brightness: Brightness.dark,
      ),
      home: const GamePage(),
    );
  }
}

const int cols = 20;
const int rows = 20;

/// ทิศ: 0 = บน, 1 = ขวา, 2 = ล่าง, 3 = ซ้าย
const List<int> dr = [-1, 0, 1, 0];
const List<int> dc = [0, 1, 0, -1];

enum GState { ready, running, paused, over }

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  final Random _rnd = Random();

  // ตำแหน่งแต่ละช่องเข้ารหัสเป็นเลขเดียว: id = row * cols + col
  final Queue<int> _body = Queue<int>(); // <- Queue: ตัวงู (first = หาง, last = หัว)
  final HashSet<int> _occupied = HashSet<int>(); // <- Hash Set: ช่องที่ตัวงูอยู่
  final HashSet<int> _obstacles = HashSet<int>(); // <- Hash Set: สิ่งกีดขวาง
  final Queue<int> _buffer = Queue<int>(); // <- Queue: คำสั่งเลี้ยวที่รออยู่

  int _dir = 1;
  int _food = 0;
  int _score = 0;
  bool _cleared = false;
  GState _state = GState.ready;
  Timer? _timer;
  final List<int> _scores = [];

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reset() {
    _timer?.cancel();
    _body.clear();
    _occupied.clear();
    _obstacles.clear();
    _buffer.clear();
    final mid = rows ~/ 2;
    for (var c = 3; c <= 5; c++) {
      final id = mid * cols + c;
      _body.addLast(id);
      _occupied.add(id);
    }
    _dir = 1;
    _score = 0;
    _cleared = false;
    _food = _spawnFood();
    _state = GState.ready;
  }

  /// สุ่มช่องว่างวางอาหาร (ช่องว่าง = ไม่อยู่ใน Hash Set ทั้งสองตัว)
  int _spawnFood() {
    final free = <int>[];
    for (var i = 0; i < rows * cols; i++) {
      if (!_occupied.contains(i) && !_obstacles.contains(i)) free.add(i);
    }
    if (free.isEmpty) return -1;
    return free[_rnd.nextInt(free.length)];
  }

  /// วางสิ่งกีดขวางในช่องว่างที่อยู่ห่างจากหัวงูพอสมควร
  void _addObstacle() {
    final head = _body.last;
    final hr = head ~/ cols, hc = head % cols;
    for (var tries = 0; tries < 60; tries++) {
      final id = _rnd.nextInt(rows * cols);
      final dist = (id ~/ cols - hr).abs() + (id % cols - hc).abs();
      if (dist > 4 &&
          id != _food &&
          !_occupied.contains(id) &&
          !_obstacles.contains(id)) {
        _obstacles.add(id);
        return;
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    final ms = max(70, 170 - _score * 4); // ยิ่งได้คะแนนมากยิ่งเร็ว
    _timer = Timer(Duration(milliseconds: ms), _tick);
  }

  void _tick() {
    if (_state != GState.running) return;

    if (_buffer.isNotEmpty) _dir = _buffer.removeFirst(); // dequeue คำสั่งเลี้ยว

    final head = _body.last;
    final r = head ~/ cols + dr[_dir];
    final c = head % cols + dc[_dir];

    // ชนขอบ
    if (r < 0 || c < 0 || r >= rows || c >= cols) {
      _finish();
      return;
    }

    final next = r * cols + c;
    final eating = next == _food;

    // ถ้าไม่ได้กิน หางจะขยับออกไป (dequeue) ก่อนเช็กชน
    if (!eating) {
      final tail = _body.removeFirst();
      _occupied.remove(tail);
    }

    // เช็กการชนใน O(1) ด้วย Hash Set
    if (_occupied.contains(next) || _obstacles.contains(next)) {
      _finish();
      return;
    }

    _body.addLast(next); // enqueue หัวใหม่
    _occupied.add(next);

    if (eating) {
      _score++;
      if (_score % 5 == 0) _addObstacle();
      _food = _spawnFood();
      if (_food < 0) {
        _cleared = true; // เต็มกระดานแล้ว ชนะ!
        _finish();
        return;
      }
    }

    setState(() {});
    _schedule();
  }

  void _finish() {
    _timer?.cancel();
    _state = GState.over;
    if (_score > 0) {
      _scores.add(_score);
      _scores.sort((a, b) => b.compareTo(a)); // Sorting: มาก -> น้อย
      if (_scores.length > 5) _scores.removeRange(5, _scores.length);
    }
    setState(() {});
  }

  void _start() {
    setState(() => _state = GState.running);
    _schedule();
  }

  void _toggle() {
    switch (_state) {
      case GState.ready:
        _start();
        break;
      case GState.running:
        _timer?.cancel();
        setState(() => _state = GState.paused);
        break;
      case GState.paused:
        _start();
        break;
      case GState.over:
        setState(_reset);
        _start();
        break;
    }
  }

  void _turn(int d) {
    if (_state == GState.over) return;
    if (_state == GState.ready) _start();
    if (_state != GState.running) return;
    final last = _buffer.isNotEmpty ? _buffer.last : _dir;
    if (d == last || d == (last + 2) % 4) return; // ห้ามเลี้ยวกลับหลัง
    if (_buffer.length < 2) _buffer.addLast(d); // enqueue
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space) {
      _toggle();
      return KeyEventResult.handled;
    }
    int? d;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyW) d = 0;
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) d = 1;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS) d = 2;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) d = 3;
    if (d == null) return KeyEventResult.ignored;
    _turn(d);
    return KeyEventResult.handled;
  }

  String get _overlayText {
    switch (_state) {
      case GState.ready:
        return 'กดลูกศร / WASD / ปุ่มเริ่ม\nเพื่อเริ่มเกม';
      case GState.paused:
        return 'หยุดชั่วคราว\n(กด Space เพื่อเล่นต่อ)';
      case GState.over:
        return _cleared
            ? '🏆 ชนะแล้ว! เต็มกระดาน\nคะแนน $_score'
            : '💥 จบเกม\nคะแนน $_score';
      case GState.running:
        return '';
    }
  }

  String get _buttonLabel {
    switch (_state) {
      case GState.ready:
        return 'เริ่ม';
      case GState.running:
        return 'หยุด';
      case GState.paused:
        return 'เล่นต่อ';
      case GState.over:
        return 'เล่นใหม่';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final best = _scores.isEmpty ? 0 : _scores.first;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('🐍 Snake Queue'), centerTitle: true),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _stat('คะแนน', '$_score'),
                      _stat('ความยาว', '${_body.length}'),
                      _stat('สูงสุด', '$best'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AspectRatio(
                    aspectRatio: 1,
                    child: GestureDetector(
                      onPanEnd: (d) {
                        final v = d.velocity.pixelsPerSecond;
                        if (v.distance < 100) return;
                        if (v.dx.abs() > v.dy.abs()) {
                          _turn(v.dx > 0 ? 1 : 3);
                        } else {
                          _turn(v.dy > 0 ? 2 : 0);
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outline, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CustomPaint(
                                painter: BoardPainter(
                                  body: _body.toList(),
                                  obstacles: Set<int>.of(_obstacles),
                                  food: _food,
                                ),
                              ),
                              if (_state != GState.running)
                                Container(
                                  color: Colors.black54,
                                  alignment: Alignment.center,
                                  child: Text(
                                    _overlayText,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ExcludeFocus(
                    child: Column(
                      children: [
                        _dpad(),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _toggle,
                          icon: Icon(_state == GState.running
                              ? Icons.pause
                              : Icons.play_arrow),
                          label: Text(_buttonLabel),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _leaderboard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      );

  Widget _dpad() {
    Widget btn(IconData icon, int d) => Padding(
          padding: const EdgeInsets.all(3),
          child: IconButton.filledTonal(
            iconSize: 30,
            onPressed: () => _turn(d),
            icon: Icon(icon),
          ),
        );
    return Column(
      children: [
        btn(Icons.keyboard_arrow_up, 0),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            btn(Icons.keyboard_arrow_left, 3),
            btn(Icons.keyboard_arrow_down, 2),
            btn(Icons.keyboard_arrow_right, 1),
          ],
        ),
      ],
    );
  }

  Widget _leaderboard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🏆 อันดับคะแนนสูงสุด (รอบนี้)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (_scores.isEmpty)
              const Text('ยังไม่มีสถิติ — เล่นให้จบเพื่อบันทึกคะแนน')
            else
              for (var i = 0; i < _scores.length; i++)
                Text('อันดับ ${i + 1}: ${_scores[i]} คะแนน'),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// วาดกระดาน
// ---------------------------------------------------------------------------

class BoardPainter extends CustomPainter {
  final List<int> body; // index 0 = หาง, ตัวสุดท้าย = หัว
  final Set<int> obstacles;
  final int food;

  BoardPainter({
    required this.body,
    required this.obstacles,
    required this.food,
  });

  Rect _cellRect(int id, double cell, {double inset = 0}) {
    final r = id ~/ cols, c = id % cols;
    return Rect.fromLTWH(
      c * cell + inset,
      r * cell + inset,
      cell - inset * 2,
      cell - inset * 2,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / cols;

    // พื้นลายหมากรุก
    final bg = Paint()..color = Colors.white.withOpacity(0.04);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if ((r + c) % 2 == 0) {
          canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell, cell), bg);
        }
      }
    }

    // สิ่งกีดขวาง
    final obsPaint = Paint()..color = Colors.blueGrey;
    for (final o in obstacles) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            _cellRect(o, cell, inset: 1), Radius.circular(cell * 0.2)),
        obsPaint,
      );
    }

    // อาหาร
    if (food >= 0) {
      final rect = _cellRect(food, cell);
      canvas.drawCircle(rect.center, cell * 0.35, Paint()..color = Colors.redAccent);
    }

    // ตัวงู
    final n = body.length;
    for (var i = 0; i < n; i++) {
      final isHead = i == n - 1;
      final shade = 0.55 + 0.45 * (i / max(1, n - 1)); // หางจางกว่า หัวเข้มกว่า
      final paint = Paint()
        ..color = isHead
            ? Colors.lightGreenAccent
            : Colors.green.withOpacity(shade);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            _cellRect(body[i], cell, inset: 1.5), Radius.circular(cell * 0.3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) => true;
}
