import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  runApp(const DiarioChecklistApp());
}

// Stati dell'impegno con colori base
enum TaskStatus {
  daFare('Da fare', Color(0xFFFF6B6B)), // Rosso
  inCorso('In corso', Color(0xFFFFD93D)), // Giallo
  completato('Completato', Color(0xFF6BCF7F)); // Verde

  final String label;
  final Color color;

  const TaskStatus(this.label, this.color);
}

// Modello dati per un task
class Task {
  final String id;
  final String titolo;
  final String descrizione;
  final DateTime data;
  TaskStatus status;

  Task({
    String? id,
    required this.titolo,
    this.descrizione = '',
    DateTime? data,
    this.status = TaskStatus.daFare,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        data = data ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'titolo': titolo,
      'descrizione': descrizione,
      'data': data.toIso8601String(),
      'status': status.name,
    };
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'],
      titolo: json['titolo'],
      descrizione: json['descrizione'] ?? '',
      data: DateTime.parse(json['data']),
      status: TaskStatus.values.byName(json['status']),
    );
  }
}

class DiarioChecklistApp extends StatelessWidget {
  const DiarioChecklistApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diario Checklist',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA), // Sfondo app neutro
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Task> _tasks = [];
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    _prefs = await SharedPreferences.getInstance();
    final tasksJson = _prefs.getStringList('tasks') ?? [];
    setState(() {
      _tasks.clear();
      for (String taskString in tasksJson) {
        try {
          final taskMap = jsonDecode(taskString) as Map<String, dynamic>;
          _tasks.add(Task.fromJson(taskMap));
        } catch (e) {
          debugPrint('Errore nel caricamento del task: $e');
        }
      }
    });
  }

  Future<void> _saveTasks() async {
    final tasksJson = _tasks.map((task) => jsonEncode(task.toJson())).toList();
    await _prefs.setStringList('tasks', tasksJson);
  }

  void _addTask(String titolo, String descrizione) {
    setState(() {
      _tasks.insert(0, Task(titolo: titolo, descrizione: descrizione));
    });
    _saveTasks();
  }

  void _updateTaskStatus(String taskId, TaskStatus newStatus) {
    setState(() {
      final task = _tasks.firstWhere((t) => t.id == taskId);
      task.status = newStatus;
    });
    _saveTasks();
  }

  void _deleteTask(String taskId) {
    setState(() {
      _tasks.removeWhere((t) => t.id == taskId);
    });
    _saveTasks();
  }

  void _showAddTaskDialog() {
    final titoloController = TextEditingController();
    final descrizioneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuovo Impegno'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titoloController,
              decoration: const InputDecoration(
                  labelText: 'Titolo *', border: OutlineInputBorder()),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descrizioneController,
              decoration: const InputDecoration(
                  labelText: 'Descrizione', border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla')),
          FilledButton(
            onPressed: () {
              if (titoloController.text.trim().isNotEmpty) {
                _addTask(titoloController.text.trim(),
                    descrizioneController.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Aggiungi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diario Checklist',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          const StatusLegend(),
          Expanded(
            child: _tasks.isEmpty
                ? const EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _tasks.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TaskCard(
                          task: _tasks[index],
                          onStatusChange: (status) =>
                              _updateTaskStatus(_tasks[index].id, status),
                          onDelete: () => _deleteTask(_tasks[index].id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskDialog,
        backgroundColor: Colors.deepPurple,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// --- LEGENDA ---
class StatusLegend extends StatelessWidget {
  const StatusLegend({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: TaskStatus.values.map((status) {
          return Row(
            children: [
              Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: status.color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(status.label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// --- CARD DEL TASK (MODIFICATA PER LEGGIBILITÀ) ---
class TaskCard extends StatelessWidget {
  final Task task;
  final Function(TaskStatus) onStatusChange;
  final VoidCallback onDelete;

  const TaskCard({
    Key? key,
    required this.task,
    required this.onStatusChange,
    required this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy, HH:mm');

    // SFONDO: Colore dello stato molto tenue (opacità 15%) per non disturbare il testo
    final Color backgroundColor = task.status.color.withOpacity(0.35);
    // TESTO: Colore quasi nero per massimo contrasto
    const Color textColor = Color(0xFF1A1A1A);
    const Color descriptionColor = Color(0xFF444444);

    return Card(
      elevation: 3,
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: task.status.color.withOpacity(0.5), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.titolo,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      decoration: task.status == TaskStatus.completato
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon:
                      const Icon(Icons.delete_outline, color: Colors.redAccent),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            if (task.descrizione.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                task.descrizione,
                style: const TextStyle(
                    fontSize: 14, color: descriptionColor, height: 1.3),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              dateFormat.format(task.data),
              style: TextStyle(
                  fontSize: 11,
                  color: textColor.withOpacity(0.6),
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            Row(
              children: TaskStatus.values.map((status) {
                final isSelected = task.status == status;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: StatusButton(
                      status: status,
                      isSelected: isSelected,
                      onPressed: () => onStatusChange(status),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// --- BOTTONI DI STATO ---
class StatusButton extends StatelessWidget {
  final TaskStatus status;
  final bool isSelected;
  final VoidCallback onPressed;
  const StatusButton(
      {Key? key,
      required this.status,
      required this.isSelected,
      required this.onPressed})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isSelected ? status.color : Colors.white.withOpacity(0.7),
          foregroundColor: isSelected ? Colors.white : Colors.black87,
          elevation: isSelected ? 2 : 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(status.label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// --- STATO VUOTO ---
class EmptyState extends StatelessWidget {
  const EmptyState({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('📋 Nessun impegno in lista.\nPremi + per iniziare!',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
    );
  }
}
