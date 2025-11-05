// main.dart for "The Morning Routine" Flutter app
// --------------------------------------------------
// This file implements a full production-ready experience that guides
// users through alarms, dynamic morning routines, and a personal feed.
// The code is intentionally well-commented to explain the architecture.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

// --------------------------------------------------
// Entry point
// --------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persistent feed entries before the UI renders so the feed is ready.
  final controller = RoutineFeedController();
  await controller.initialize();

  runApp(
    RoutineFeedScope(
      controller: controller,
      child: const MorningRoutineApp(),
    ),
  );
}

// --------------------------------------------------
// Root application widget
// --------------------------------------------------
class MorningRoutineApp extends StatelessWidget {
  const MorningRoutineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'The Morning Routine',
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF5D3FD3),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5D3FD3),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F2FF),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Color(0xFF2C1A73),
          titleTextStyle: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C1A73),
          ),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2C1A73),
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            height: 1.4,
            color: Color(0xFF3C2F80),
          ),
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// --------------------------------------------------
// Shared feed controller + scope
// --------------------------------------------------
class RoutineFeedScope extends InheritedNotifier<RoutineFeedController> {
  const RoutineFeedScope({
    required RoutineFeedController controller,
    required Widget child,
    super.key,
  }) : super(notifier: controller, child: child);

  static RoutineFeedController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<RoutineFeedScope>();
    assert(scope != null, 'RoutineFeedScope not found in the widget tree.');
    return scope!.notifier!;
  }
}

class RoutineFeedController extends ChangeNotifier {
  RoutineFeedController();

  static const String storageKey = 'routine_feed_entries';
  final List<RoutineEntry> _entries = <RoutineEntry>[];

  UnmodifiableListView<RoutineEntry> get entries =>
      UnmodifiableListView<RoutineEntry>(_entries);

  SharedPreferences? _prefs;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs!.getString(storageKey);
    if (stored != null) {
      final decoded = jsonDecode(stored) as List<dynamic>;
      _entries
        ..clear()
        ..addAll(
          decoded
              .map((dynamic item) =>
                  RoutineEntry.fromJson(item as Map<String, dynamic>))
              .toList(),
        );
    }
  }

  Future<void> addEntry(RoutineEntry entry) async {
    _entries.insert(0, entry);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    if (_prefs == null) return;
    final encoded = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await _prefs!.setString(storageKey, encoded);
  }
}

// --------------------------------------------------
// Data models for routine + feed
// --------------------------------------------------
enum RoutineTaskType { photo, task, info }

class RoutineTask {
  const RoutineTask({
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
    this.actionLabel,
    this.secondaryActionLabel,
  });

  final RoutineTaskType type;
  final String title;
  final String description;
  final IconData icon;
  final String? actionLabel;
  final String? secondaryActionLabel;
}

class RoutineTaskResult {
  RoutineTaskResult({
    required this.taskTitle,
    required this.taskType,
    required this.description,
    this.imageBytes,
  });

  final String taskTitle;
  final RoutineTaskType taskType;
  final String description;
  final Uint8List? imageBytes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'taskTitle': taskTitle,
        'taskType': taskType.name,
        'description': description,
        'imageBytes': imageBytes != null ? base64Encode(imageBytes!) : null,
      };

  factory RoutineTaskResult.fromJson(Map<String, dynamic> json) {
    return RoutineTaskResult(
      taskTitle: json['taskTitle'] as String,
      taskType: RoutineTaskType.values
          .firstWhere((e) => e.name == json['taskType']),
      description: json['description'] as String,
      imageBytes: json['imageBytes'] != null
          ? base64Decode(json['imageBytes'] as String)
          : null,
    );
  }
}

class RoutineEntry {
  RoutineEntry({
    required this.timestamp,
    required this.results,
  });

  final DateTime timestamp;
  final List<RoutineTaskResult> results;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'timestamp': timestamp.toIso8601String(),
        'results': results.map((r) => r.toJson()).toList(),
      };

  factory RoutineEntry.fromJson(Map<String, dynamic> json) {
    return RoutineEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      results: (json['results'] as List<dynamic>)
          .map((dynamic item) =>
              RoutineTaskResult.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

// --------------------------------------------------
// Home page with bottom navigation
// --------------------------------------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  late final GlobalKey<MorningRoutineTabState> _routineKey;

  @override
  void initState() {
    super.initState();
    _routineKey = GlobalKey<MorningRoutineTabState>();
  }

  void _handleAlarmDismissed() {
    setState(() => _selectedIndex = 1);
    _routineKey.currentState?.startRoutine();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      AlarmTab(onAlarmDismissed: _handleAlarmDismissed),
      MorningRoutineTab(key: _routineKey),
      const FeedTab(),
      const ProfileTab(),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: tabs,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0x225D3FD3),
        selectedIndex: _selectedIndex,
        elevation: 10,
        height: 70,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.alarm_outlined),
            selectedIcon: Icon(Icons.alarm),
            label: 'Alarms',
          ),
          NavigationDestination(
            icon: Icon(Icons.sunny),
            selectedIcon: Icon(Icons.sunny_snowing),
            label: 'Routine',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome),
            selectedIcon: Icon(Icons.auto_awesome_mosaic),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// Alarm tab implementation
// --------------------------------------------------
class AlarmTab extends StatefulWidget {
  const AlarmTab({
    required this.onAlarmDismissed,
    super.key,
  });

  final VoidCallback onAlarmDismissed;

  @override
  State<AlarmTab> createState() => _AlarmTabState();
}

class _AlarmTabState extends State<AlarmTab> {
  TimeOfDay _selectedTime = TimeOfDay.now();
  Timer? _alarmTimer;
  bool _isRinging = false;
  String _statusMessage = 'No alarm scheduled';
  final AudioPlayer _player = AudioPlayer();
  Uint8List? _alarmToneCache;

  @override
  void dispose() {
    _alarmTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _scheduleAlarm() async {
    _alarmTimer?.cancel();
    final now = DateTime.now();
    var alarmTime = DateTime(
      now.year,
      now.month,
      now.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    if (alarmTime.isBefore(now)) {
      alarmTime = alarmTime.add(const Duration(days: 1));
    }
    final delay = alarmTime.difference(now);

    setState(() {
      _statusMessage =
          'Alarm set for ${DateFormat.jm().format(alarmTime)} (${_formatDuration(delay)} from now)';
    });

    _alarmTimer = Timer(delay, _triggerAlarm);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours == 0) {
      return '$minutes minute${minutes == 1 ? '' : 's'}';
    }
    return '$hours hour${hours == 1 ? '' : 's'} $minutes minute${minutes == 1 ? '' : 's'}';
  }

  Future<void> _triggerAlarm() async {
    setState(() {
      _isRinging = true;
      _statusMessage = 'Alarm ringing! Rise and shine!';
    });
    await _player.setReleaseMode(ReleaseMode.loop);
    final bytes = await _loadAlarmToneBytes();
    await _player.play(BytesSource(bytes));
  }

  Future<void> _dismissAlarm() async {
    await _player.stop();
    setState(() {
      _isRinging = false;
      _statusMessage = 'Alarm dismissed. Let\'s begin the routine!';
    });
    widget.onAlarmDismissed();
  }

  Future<Uint8List> _loadAlarmToneBytes() async {
    if (_alarmToneCache != null) {
      return _alarmToneCache!;
    }
    // The alarm tone is stored as a base64-encoded text asset so the project
    // avoids committing binary files while still shipping an offline sound.
    final encoded = await rootBundle.loadString('assets/sounds/alarm_tone.b64');
    final normalized = encoded.replaceAll('\n', '').trim();
    _alarmToneCache = base64Decode(normalized);
    return _alarmToneCache!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Alarms', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          _buildGradientCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose your wake up time',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C1A73),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    height: 200,
                    child: CupertinoTheme(
                      data: const CupertinoThemeData(
                        brightness: Brightness.light,
                        primaryColor: Color(0xFF5D3FD3),
                      ),
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.time,
                        use24hFormat: false,
                        initialDateTime: DateTime(
                          2020,
                          1,
                          1,
                          _selectedTime.hour,
                          _selectedTime.minute,
                        ),
                        onDateTimeChanged: (value) {
                          setState(() {
                            _selectedTime = TimeOfDay(
                              hour: value.hour,
                              minute: value.minute,
                            );
                          });
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _scheduleAlarm,
                  icon: const Icon(Icons.alarm_add),
                  label: const Text('Schedule Alarm'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5D3FD3),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _statusMessage,
                  style: const TextStyle(color: Color(0xFF4A3F91)),
                ),
                if (_isRinging) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _dismissAlarm,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Dismiss Alarm'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF15BB5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildInfoTipCard(),
        ],
      ),
    );
  }

  Widget _buildInfoTipCard() {
    return _buildGradientCard(
      colors: const [Color(0xFF9573F1), Color(0xFFB388FF)],
      child: Row(
        children: const [
          Icon(Icons.lightbulb_outline, color: Colors.white, size: 40),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              'Tip: Align your alarm with a consistent bedtime to wake up refreshed. Consistency makes mornings easier! ',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// Morning routine tab
// --------------------------------------------------
class MorningRoutineTab extends StatefulWidget {
  const MorningRoutineTab({super.key});

  @override
  State<MorningRoutineTab> createState() => MorningRoutineTabState();
}

class MorningRoutineTabState extends State<MorningRoutineTab> {
  final List<RoutineTask> _tasks = _defaultRoutineTasks;
  final List<RoutineTaskResult> _completed = <RoutineTaskResult>[];
  final ImagePicker _picker = ImagePicker();
  int _currentIndex = 0;
  bool _isRunning = false;
  bool _isCompleted = false;
  bool _isPosting = false;

  static const String _mockPhotoBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAMgAAADICAYAAACtWK6eAAAACXBIWXMAAAsSAAALEgHS3X78AAACD0lEQVR4nO3SMQ0AAAgDINc/9K3hHBwwqNpmAAD4HEiEBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAIF7AQLnAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAG/AQZHEs/xAAAAAElFTkSuQmCC';

  Uint8List get _mockPhotoBytes => base64Decode(_mockPhotoBase64);

  void startRoutine() {
    setState(() {
      _isRunning = true;
      _isCompleted = false;
      _currentIndex = 0;
      _completed.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Morning Routine', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.1),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _buildContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (!_isRunning && !_isCompleted) {
      return _buildWelcomeCard(context);
    }

    if (_isCompleted) {
      return _buildCompletionCard(context);
    }

    final task = _tasks[_currentIndex];
    final progress = (_currentIndex) / _tasks.length;

    return Column(
      key: ValueKey<int>(_currentIndex),
      children: [
        LinearProgressIndicator(
          value: progress,
          minHeight: 10,
          backgroundColor: const Color(0x225D3FD3),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5D3FD3)),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _buildGradientCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0x225D3FD3),
                      child: Icon(task.icon, color: const Color(0xFF5D3FD3), size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        task.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2C1A73),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      task.description,
                      style: const TextStyle(fontSize: 16, color: Color(0xFF3C2F80)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildTaskAction(context, task),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeCard(BuildContext context) {
    return Center(
      child: _buildGradientCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ready to crush your morning?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2C1A73),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Follow the guided steps to stretch, nourish, and motivate yourself for the perfect day ahead.',
              style: TextStyle(fontSize: 16, color: Color(0xFF3C2F80)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: startRoutine,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF5D3FD3),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              ),
              child: const Text('Start My Routine'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskAction(BuildContext context, RoutineTask task) {
    switch (task.type) {
      case RoutineTaskType.task:
        return FilledButton(
          onPressed: () => _completeTask(),
          style: _primaryButtonStyle,
          child: Text(task.actionLabel ?? 'Mark Complete'),
        );
      case RoutineTaskType.info:
        return FilledButton(
          onPressed: () => _completeTask(),
          style: _primaryButtonStyle,
          child: Text(task.actionLabel ?? 'Next Insight'),
        );
      case RoutineTaskType.photo:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () => _capturePhoto(context),
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(task.actionLabel ?? 'Take Photo'),
              style: _primaryButtonStyle,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _simulatePhoto(),
              icon: const Icon(Icons.wb_sunny),
              label: Text(task.secondaryActionLabel ?? 'Simulate Photo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF5D3FD3),
                side: const BorderSide(color: Color(0xFF5D3FD3)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
            ),
          ],
        );
    }
  }

  ButtonStyle get _primaryButtonStyle => FilledButton.styleFrom(
        backgroundColor: const Color(0xFF5D3FD3),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      );

  Future<void> _capturePhoto(BuildContext context) async {
    try {
      final source = kIsWeb ? ImageSource.camera : ImageSource.camera;
      final file = await _picker.pickImage(source: source, maxHeight: 1080);
      if (file != null) {
        final bytes = await file.readAsBytes();
        _completeTask(photoBytes: bytes);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No photo captured. Try again!')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Camera unavailable (${error.runtimeType}). Using simulated photo instead.',
          ),
        ),
      );
      _simulatePhoto();
    }
  }

  void _simulatePhoto() {
    _completeTask(photoBytes: _mockPhotoBytes);
  }

  void _completeTask({Uint8List? photoBytes}) {
    final task = _tasks[_currentIndex];
    _completed.add(
      RoutineTaskResult(
        taskTitle: task.title,
        taskType: task.type,
        description: task.description,
        imageBytes: photoBytes,
      ),
    );

    if (_currentIndex + 1 >= _tasks.length) {
      setState(() {
        _isRunning = false;
        _isCompleted = true;
      });
    } else {
      setState(() {
        _currentIndex++;
      });
    }
  }

  Widget _buildCompletionCard(BuildContext context) {
    final controller = RoutineFeedScope.of(context);
    return _buildGradientCard(
      key: const ValueKey<String>('completion-card'),
      child: Column(
        children: [
          const Text(
            'Routine Complete!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2C1A73),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'You crushed it! Share your glow-up and keep the streak alive.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Color(0xFF3C2F80)),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: _completed.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = _completed[index];
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0x225D3FD3),
                        child: Icon(
                          item.taskType == RoutineTaskType.photo
                              ? Icons.camera_alt
                              : item.taskType == RoutineTaskType.task
                                  ? Icons.check_circle
                                  : Icons.menu_book,
                          color: const Color(0xFF5D3FD3),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.taskTitle,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2C1A73),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF3C2F80),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (item.imageBytes != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              item.imageBytes!,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isPosting
                ? null
                : () async {
                    setState(() => _isPosting = true);
                    await controller.addEntry(
                      RoutineEntry(
                        timestamp: DateTime.now(),
                        results: List<RoutineTaskResult>.from(_completed),
                      ),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Routine shared to feed!')),
                      );
                    }
                    setState(() => _isPosting = false);
                  },
            icon: const Icon(Icons.send_outlined),
            label: Text(_isPosting ? 'Sharing...' : 'Share to Feed'),
            style: _primaryButtonStyle,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: startRoutine,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF5D3FD3),
              side: const BorderSide(color: Color(0xFF5D3FD3)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Text('Restart Routine'),
          ),
        ],
      ),
    );
  }
}

// Default routine tasks used by the app.
final List<RoutineTask> _defaultRoutineTasks = <RoutineTask>[
  const RoutineTask(
    type: RoutineTaskType.task,
    title: 'Wake-Up Breathwork',
    description:
        'Sit up straight, close your eyes, and take five deep belly breaths. Focus on feeling gratitude with each inhale.',
    icon: Icons.self_improvement,
    actionLabel: 'I completed my breaths',
  ),
  const RoutineTask(
    type: RoutineTaskType.info,
    title: 'Hydration Hack',
    description:
        'Drink a glass of water with a squeeze of lemon. Hydration jump-starts your metabolism and improves energy levels.',
    icon: Icons.local_drink,
    actionLabel: 'Hydrated and ready',
  ),
  const RoutineTask(
    type: RoutineTaskType.task,
    title: 'Stretch & Shine',
    description:
        'Perform a gentle full-body stretch: reach high, twist side-to-side, and roll your shoulders to loosen tension.',
    icon: Icons.accessibility_new,
    actionLabel: 'Stretched it out',
  ),
  const RoutineTask(
    type: RoutineTaskType.photo,
    title: 'Morning Glow Selfie',
    description:
        'Capture your refreshed face to celebrate progress. Snap a photo or simulate one if you are camera-shy today.',
    icon: Icons.camera_alt_outlined,
    actionLabel: 'Open Camera',
    secondaryActionLabel: 'Simulate Photo',
  ),
  const RoutineTask(
    type: RoutineTaskType.info,
    title: 'Breakfast Inspiration',
    description:
        'Choose a protein-rich breakfast. Try Greek yogurt with berries or avocado toast to keep energy steady.',
    icon: Icons.breakfast_dining,
    actionLabel: 'Sounds delicious',
  ),
  const RoutineTask(
    type: RoutineTaskType.task,
    title: 'Mindful Mirror Moment',
    description:
        'Stand in front of the mirror, look yourself in the eyes, and repeat: "I am worthy. I am energized. I own today."',
    icon: Icons.mood,
    actionLabel: 'Affirmed and smiling',
  ),
  const RoutineTask(
    type: RoutineTaskType.photo,
    title: 'Healthy Plate Snapshot',
    description:
        'Snap a quick photo of your nourishing breakfast to keep track of your wins.',
    icon: Icons.brunch_dining,
    actionLabel: 'Capture meal',
    secondaryActionLabel: 'Simulate meal photo',
  ),
  const RoutineTask(
    type: RoutineTaskType.info,
    title: 'Quick Motivation',
    description:
        'Reminder: Consistent routines build unstoppable momentum. Celebrate your small wins—they add up!',
    icon: Icons.auto_awesome,
    actionLabel: 'Finish strong',
  ),
];

// --------------------------------------------------
// Feed tab
// --------------------------------------------------
class FeedTab extends StatelessWidget {
  const FeedTab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = RoutineFeedScope.of(context);
    final entries = controller.entries;

    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildGradientCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.auto_awesome, size: 48, color: Colors.white),
                SizedBox(height: 12),
                Text(
                  'No routines shared yet',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Complete your routine and tap "Share to Feed" to build your motivational gallery.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _FeedEntryCard(entry: entry, index: index);
      },
    );
  }
}

class _FeedEntryCard extends StatelessWidget {
  const _FeedEntryCard({
    required this.entry,
    required this.index,
  });

  final RoutineEntry entry;
  final int index;

  @override
  Widget build(BuildContext context) {
    final timestamp = DateFormat('EEE, MMM d • h:mm a').format(entry.timestamp);
    final hasPhotos = entry.results.any((r) => r.imageBytes != null);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: hasPhotos
              ? const [Color(0xFF7F5AF0), Color(0xFF9C6BFF)]
              : const [Color(0xFF5D3FD3), Color(0xFF7C53E6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Morning Victory #${index + 1}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              timestamp,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            if (hasPhotos) _buildPhotoRow(entry),
            const SizedBox(height: 12),
            ...entry.results.map(
              (result) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      result.taskType == RoutineTaskType.photo
                          ? Icons.camera_alt
                          : result.taskType == RoutineTaskType.task
                              ? Icons.check_circle
                              : Icons.menu_book,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.taskTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            result.description,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoRow(RoutineEntry entry) {
    final photos = entry.results.where((r) => r.imageBytes != null);
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final result = photos.elementAt(index);
          return ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.memory(
              result.imageBytes!,
              width: 90,
              height: 90,
              fit: BoxFit.cover,
            ),
          );
        },
      ),
    );
  }
}

// --------------------------------------------------
// Profile tab placeholder
// --------------------------------------------------
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _buildGradientCard(
        colors: const [Color(0xFF5D3FD3), Color(0xFFB388FF)],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.person_outline, size: 64, color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Profile Coming Soon',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'We\'re crafting personalized stats and streaks just for you. Stay tuned!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------
// Shared UI helpers
// --------------------------------------------------
Widget _buildGradientCard({
  required Widget child,
  Key? key,
  List<Color> colors = const [Color(0xFFE8E2FF), Color(0xFFF4EDFF)],
}) {
  return Container(
    key: key,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    padding: const EdgeInsets.all(24),
    child: child,
  );
}
