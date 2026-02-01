import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  runApp(const DiarioChecklistApp());
}

// Stati dell'impegno con colori
enum TaskStatus {
  daFare('Da fare', Color(0xFFFF6B6B)),      // Rosso
  inCorso('In corso', Color(0xFFFFD93D)),    // Giallo
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

  // Serializzazione
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'titolo': titolo,
      'descrizione': descrizione,
      'data': data.toIso8601String(),
      'status': status.name,
    };
  }

  // Deserializzazione
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
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
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
          print('Errore nel caricamento del task: $e');
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
      _tasks.add(Task(titolo: titolo, descrizione: descrizione));
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
                labelText: 'Titolo *',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descrizioneController,
              decoration: const InputDecoration(
                labelText: 'Descrizione (opzionale)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              if (titoloController.text.trim().isNotEmpty) {
                _addTask(
                  titoloController.text.trim(),
                  descrizioneController.text.trim(),
                );
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
        title: const Text(
          'Diario Checklist',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Legenda stati
          const StatusLegend(),
          
          // Lista tasks
          Expanded(
            child: _tasks.isEmpty
                ? const EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _tasks.length,
                    itemBuilder: (context, index) {
                      final task = _tasks[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TaskCard(
                          task: task,
                          onStatusChange: (status) =>
                              _updateTaskStatus(task.id, status),
                          onDelete: () => _deleteTask(task.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskDialog,
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class StatusLegend extends StatelessWidget {
  const StatusLegend({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: TaskStatus.values.map((status) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: status.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  status.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

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

    return Card(
      elevation: 4,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: task.status.color,
          width: 3,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con titolo e pulsante elimina
            Row(
              children: [
                // Indicatore colorato
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: task.status.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                
                // Titolo
                Expanded(
                  child: Text(
                    task.titolo,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      decoration: task.status == TaskStatus.completato
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                
                // Pulsante elimina
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete, color: Colors.red),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            
            // Descrizione
            if (task.descrizione.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task.descrizione,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
            
            // Data
            const SizedBox(height: 8),
            Text(
              dateFormat.format(task.data),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w300,
              ),
            ),
            
            // Pulsanti stato
            const SizedBox(height: 12),
            Row(
              children: TaskStatus.values.map((status) {
                final isSelected = task.status == status;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
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

class StatusButton extends StatelessWidget {
  final TaskStatus status;
  final bool isSelected;
  final VoidCallback onPressed;

  const StatusButton({
    Key? key,
    required this.status,
    required this.isSelected,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected
              ? status.color
              : Colors.grey.shade300.withOpacity(0.3),
          foregroundColor: isSelected ? Colors.white : Colors.grey.shade700,
          elevation: isSelected ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(
          status.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Text(
            '📋',
            style: TextStyle(fontSize: 64),
          ),
          SizedBox(height: 16),
          Text(
            'Nessun impegno in lista',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Premi + per aggiungerne uno',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
