import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'dart:convert';
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

// ⚠️ غيّر هذا عند تغيير الشبكة
const String piIp = '192.168.0.53';
const int piPort = 8765;

void main() => runApp(const ECGApp());

class ECGApp extends StatelessWidget {
  const ECGApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cardio Monitor',
      theme: ThemeData(
        fontFamily: 'Arial',
        scaffoldBackgroundColor: const Color(0xFF0A0E27),
      ),
      home: const ECGMonitor(),
    );
  }
}

class ECGMonitor extends StatefulWidget {
  const ECGMonitor({super.key});

  @override
  State<ECGMonitor> createState() => _ECGMonitorState();
}

class _ECGMonitorState extends State<ECGMonitor> with TickerProviderStateMixin {
  WebSocketChannel? channel;
  StreamSubscription? subscription;
  
  int bpm = 0;
  double temperature = 36.6;
  double ecgVoltage = 0.0;
  String quality = "جاري التحليل";
  bool leadsOk = false;
  List<String> alerts = [];
  bool isConnected = false;
  
  final Queue<double> ecgBuffer = Queue<double>();
  static const int BUFFER_SIZE = 400;
  
  late AnimationController _heartController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < BUFFER_SIZE; i++) {
      ecgBuffer.add(1.5);
    }
    
    _heartController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    _connect();
  }

  void _connect() {
    try {
      channel = WebSocketChannel.connect(Uri.parse('ws://$piIp:$piPort'));
      subscription = channel!.stream.listen(
        (data) {
          try {
            final j = json.decode(data.toString());
            setState(() {
              isConnected = true;
              bpm = j['bpm'] ?? 0;
              temperature = (j['temp'] ?? 36.6).toDouble();
              ecgVoltage = (j['ecg_voltage'] ?? 0.0).toDouble();
              quality = j['quality'] ?? "جاري التحليل";
              leadsOk = j['leads_ok'] ?? false;
              alerts = List<String>.from(j['alerts'] ?? []);
              
              ecgBuffer.addLast(ecgVoltage);
              if (ecgBuffer.length > BUFFER_SIZE) ecgBuffer.removeFirst();
            });
          } catch (e) {}
        },
        onDone: () {
          setState(() => isConnected = false);
          _reconnect();
        },
        onError: (e) {
          setState(() => isConnected = false);
          _reconnect();
        },
      );
    } catch (e) {
      setState(() => isConnected = false);
      _reconnect();
    }
  }

  void _reconnect() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _connect();
    });
  }

  @override
  void dispose() {
    _heartController.dispose();
    _pulseController.dispose();
    subscription?.cancel();
    channel?.sink.close(status.goingAway);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A0E27),
              Color(0xFF1A1F3A),
              Color(0xFF0A0E27),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 12),
                _buildECGMonitor(),
                const SizedBox(height: 16),
                _buildVitalsRow(),
                const SizedBox(height: 16),
                _buildStatusCard(),
                if (alerts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildAlerts(),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900.withOpacity(0.3), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _heartController,
            builder: (_, __) => Transform.scale(
              scale: 1 + (_heartController.value * 0.15),
              child: const Icon(Icons.favorite, color: Color(0xFFFF4757), size: 36),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CARDIO MONITOR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  'نظام مراقبة القلب',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          _buildConnectionBadge(),
        ],
      ),
    );
  }

  Widget _buildConnectionBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isConnected 
            ? const Color(0xFF00E676).withOpacity(0.15) 
            : Colors.red.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected ? const Color(0xFF00E676) : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isConnected ? const Color(0xFF00E676) : Colors.red,
                shape: BoxShape.circle,
                boxShadow: isConnected ? [
                  BoxShadow(
                    color: const Color(0xFF00E676).withOpacity(0.6 * (1 - _pulseController.value)),
                    blurRadius: 8 * _pulseController.value,
                    spreadRadius: 4 * _pulseController.value,
                  ),
                ] : [],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              color: isConnected ? const Color(0xFF00E676) : Colors.red,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildECGMonitor() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF000814),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E676).withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            CustomPaint(
              painter: ECGPainter(ecgBuffer.toList()),
              size: Size.infinite,
            ),
            Positioned(
              top: 8,
              left: 12,
              child: Row(
                children: [
                  const Icon(Icons.show_chart, color: Color(0xFF00E676), size: 16),
                  const SizedBox(width: 4),
                  const Text(
                    'ECG',
                    style: TextStyle(
                      color: Color(0xFF00E676),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '250 Hz',
                    style: TextStyle(
                      color: const Color(0xFF00E676).withOpacity(0.6),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 12,
              child: Text(
                quality,
                style: TextStyle(
                  color: const Color(0xFF00E676).withOpacity(0.8),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVitalsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(child: _buildBPMCard()),
          const SizedBox(width: 12),
          Expanded(child: _buildTempCard()),
        ],
      ),
    );
  }

  Widget _buildBPMCard() {
    final bpmColor = bpm == 0 
        ? Colors.grey 
        : (bpm < 60 || bpm > 100) ? const Color(0xFFFF4757) : const Color(0xFF00E676);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bpmColor.withOpacity(0.15),
            bpmColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bpmColor.withOpacity(0.4), width: 1),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  AnimatedBuilder(
                    animation: _heartController,
                    builder: (_, __) => Transform.scale(
                      scale: bpm > 0 ? 1 + (_heartController.value * 0.2) : 1,
                      child: Icon(Icons.favorite, color: bpmColor, size: 20),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'HEART RATE',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            bpm > 0 ? '$bpm' : '--',
            style: TextStyle(
              color: bpmColor,
              fontSize: 56,
              fontWeight: FontWeight.w900,
              height: 1,
              shadows: [
                Shadow(color: bpmColor.withOpacity(0.5), blurRadius: 20),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'BPM',
            style: TextStyle(
              color: bpmColor.withOpacity(0.8),
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            bpm == 0 ? 'لا يوجد' : (bpm < 60) ? 'بطء' : (bpm > 100) ? 'تسارع' : 'طبيعي',
            style: TextStyle(color: bpmColor, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildTempCard() {
    final tempColor = (temperature > 37.5 || temperature < 36.0) 
        ? const Color(0xFFFFA502) 
        : const Color(0xFF3498DB);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tempColor.withOpacity(0.15),
            tempColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tempColor.withOpacity(0.4), width: 1),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.thermostat, color: tempColor, size: 20),
                  const SizedBox(width: 6),
                  const Text(
                    'TEMPERATURE',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            temperature.toStringAsFixed(1),
            style: TextStyle(
              color: tempColor,
              fontSize: 56,
              fontWeight: FontWeight.w900,
              height: 1,
              shadows: [
                Shadow(color: tempColor.withOpacity(0.5), blurRadius: 20),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '°C',
            style: TextStyle(
              color: tempColor.withOpacity(0.8),
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            (temperature > 37.5) ? 'مرتفعة' : (temperature < 36.0) ? 'منخفضة' : 'طبيعية',
            style: TextStyle(color: tempColor, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(
            leadsOk ? Icons.check_circle : Icons.warning_amber,
            color: leadsOk ? const Color(0xFF00E676) : const Color(0xFFFFA502),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              leadsOk ? 'الأقطاب موصولة بشكل صحيح' : 'ضع الأقطاب على الصدر',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlerts() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF4757).withOpacity(0.2),
            const Color(0xFFFF4757).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF4757).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notifications_active, color: Color(0xFFFF4757), size: 18),
              SizedBox(width: 8),
              Text(
                'تنبيهات',
                style: TextStyle(
                  color: Color(0xFFFF4757),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...alerts.map((a) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                const Icon(Icons.arrow_left, color: Color(0xFFFF4757), size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    a,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class ECGPainter extends CustomPainter {
  final List<double> data;
  ECGPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    // Grid
    final gridPaint = Paint()
      ..color = const Color(0xFF00E676).withOpacity(0.08)
      ..strokeWidth = 0.5;
    
    for (double x = 0; x < size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    
    // Major grid
    final majorGrid = Paint()
      ..color = const Color(0xFF00E676).withOpacity(0.15)
      ..strokeWidth = 0.8;
    for (double x = 0; x < size.width; x += 100) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), majorGrid);
    }
    for (double y = 0; y < size.height; y += 100) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), majorGrid);
    }
    
    if (data.isEmpty) return;
    
    // Glow effect
    final glow = Paint()
      ..color = const Color(0xFF00E676).withOpacity(0.3)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    
    final line = Paint()
      ..color = const Color(0xFF00E676)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    final path = Path();
    final stepX = size.width / data.length;
    
    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalized = (data[i] / 3.3).clamp(0.0, 1.0);
      final y = size.height - (normalized * size.height * 0.9) - (size.height * 0.05);
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    
    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(ECGPainter oldDelegate) => true;
}