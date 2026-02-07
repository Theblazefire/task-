import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  runApp(const DiarioChecklistApp());
}

// Stati dell'impegno con colori
enum TaskStatus {
  daFare('Da fare', Color(0xFFFF6B6B)),
  inCorso('In corso', Color(0xFFFFD93D)),
  completato('Completato', Color(0xFF6BCF7F));

  final String label;
  final Color color;
  
  const TaskStatus(this.label, this.color);
  
  // Conversione da/per JSON
  static TaskStatus fromString(String status) {
    return TaskStatus.values.firstWhere(
      (e) => e.name == status,
      orElse: () => TaskStatus.daFare,
    );
  }
}

// Modello per un Task
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

  // Conversione a JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'titolo': titolo,
      'descrizione': descrizione,
      'data': data.toIso8601String(),
      'status': status.name,
    };
  }

  // Creazione da JSON
  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'],
      titolo: json['titolo'],
      descrizione: json['descrizione'] ?? '',
      data: DateTime.parse(json['data']),
      status: TaskStatus.fromString(json['status']),
    );
  }
}

// Modello per un Progetto
class Project {
  final String id;
  final String nome;
  final String descrizione;
  final Color colore;
  final IconData icona;
  final DateTime dataCreazione;
  final List<Task> tasks;

  Project({
    String? id,
    required this.nome,
    this.descrizione = '',
    this.colore = Colors.blue,
    this.icona = Icons.folder,
    DateTime? dataCreazione,
    List<Task>? tasks,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        dataCreazione = dataCreazione ?? DateTime.now(),
        tasks = tasks ?? [];

  int get totaleTask => tasks.length;
  int get taskCompletati => tasks.where((t) => t.status == TaskStatus.completato).length;
  int get taskInCorso => tasks.where((t) => t.status == TaskStatus.inCorso).length;
  int get taskDaFare => tasks.where((t) => t.status == TaskStatus.daFare).length;
  double get percentualeCompletamento => 
      totaleTask > 0 ? (taskCompletati / totaleTask * 100) : 0;

  // Conversione a JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'descrizione': descrizione,
      'colore': colore.value,
      'icona': icona.codePoint,
      'dataCreazione': dataCreazione.toIso8601String(),
      'tasks': tasks.map((t) => t.toJson()).toList(),
    };
  }

  // Creazione da JSON
  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      nome: json['nome'],
      descrizione: json['descrizione'] ?? '',
      colore: Color(json['colore']),
      icona: IconData(json['icona'], fontFamily: 'MaterialIcons'),
      dataCreazione: DateTime.parse(json['dataCreazione']),
      tasks: (json['tasks'] as List?)?.map((t) => Task.fromJson(t)).toList() ?? [],
    );
  }
}

// Servizio per salvare/caricare dati
class StorageService {
  static const String _keyProjects = 'projects_data';

  // Salva tutti i progetti
  static Future<void> saveProjects(List<Project> projects) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = projects.map((p) => p.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await prefs.setString(_keyProjects, jsonString);
    print('💾 Salvati ${projects.length} progetti');
  }

  // Carica tutti i progetti
  static Future<List<Project>> loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_keyProjects);
    
    if (jsonString == null || jsonString.isEmpty) {
      print('📂 Nessun dato salvato trovato');
      return [];
    }
    
    try {
      final jsonList = jsonDecode(jsonString) as List;
      final projects = jsonList.map((json) => Project.fromJson(json)).toList();
      print('📂 Caricati ${projects.length} progetti');
      return projects;
    } catch (e) {
      print('❌ Errore nel caricamento: $e');
      return [];
    }
  }

  // Cancella tutti i dati
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyProjects);
    print('🗑️ Tutti i dati cancellati');
  }
}

class DiarioChecklistApp extends StatelessWidget {
  const DiarioChecklistApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestione Progetti',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      home: const ProjectsHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ProjectsHomePage extends StatefulWidget {
  const ProjectsHomePage({Key? key}) : super(key: key);

  @override
  State<ProjectsHomePage> createState() => _ProjectsHomePageState();
}

class _ProjectsHomePageState extends State<ProjectsHomePage> {
  List<Project> _projects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Carica i dati all'avvio
  Future<void> _loadData() async {
    final projects = await StorageService.loadProjects();
    setState(() {
      _projects = projects;
      _isLoading = false;
    });
  }

  // Salva i dati ogni volta che cambiano
  Future<void> _saveData() async {
    await StorageService.saveProjects(_projects);
  }

  void _addProject(String nome, String descrizione, Color colore, IconData icona) {
    setState(() {
      _projects.add(Project(
        nome: nome,
        descrizione: descrizione,
        colore: colore,
        icona: icona,
      ));
    });
    _saveData();
  }

  void _deleteProject(String projectId) {
    setState(() {
      _projects.removeWhere((p) => p.id == projectId);
    });
    _saveData();
  }

  void _showAddProjectDialog() {
    final nomeController = TextEditingController();
    final descrizioneController = TextEditingController();
    Color selectedColor = Colors.blue;
    IconData selectedIcon = Icons.folder;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuovo Progetto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomeController,
                  decoration: const InputDecoration(
                    labelText: 'Nome Progetto *',
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
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                const Text('Colore:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    Colors.blue,
                    Colors.red,
                    Colors.green,
                    Colors.orange,
                    Colors.purple,
                    Colors.teal,
                    Colors.pink,
                    Colors.brown,
                  ].map((color) {
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedColor = color),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selectedColor == color ? Colors.black : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text('Icona:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    Icons.folder,
                    Icons.work,
                    Icons.school,
                    Icons.home,
                    Icons.fitness_center,
                    Icons.shopping_cart,
                    Icons.code,
                    Icons.palette,
                  ].map((icon) {
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedIcon = icon),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: selectedIcon == icon ? Colors.grey.shade300 : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: selectedColor),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                if (nomeController.text.trim().isNotEmpty) {
                  _addProject(
                    nomeController.text.trim(),
                    descrizioneController.text.trim(),
                    selectedColor,
                    selectedIcon,
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text('Crea'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'I Miei Progetti',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Pulsante per cancellare tutti i dati
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Cancella tutti i dati',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Conferma'),
                  content: const Text('Vuoi cancellare TUTTI i progetti e i task? Questa azione non può essere annullata.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annulla'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Cancella Tutto'),
                    ),
                  ],
                ),
              );
              
              if (confirm == true) {
                await StorageService.clearAll();
                setState(() {
                  _projects.clear();
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tutti i dati sono stati cancellati')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: _projects.isEmpty
          ? const EmptyProjectsState()
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.85,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _projects.length,
              itemBuilder: (context, index) {
                final project = _projects[index];
                return ProjectCard(
                  project: project,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProjectDetailPage(
                          project: project,
                          onChanged: _saveData,
                        ),
                      ),
                    );
                    setState(() {}); // Aggiorna statistiche
                  },
                  onDelete: () => _deleteProject(project.id),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProjectDialog,
        backgroundColor: Theme.of(context).primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nuovo Progetto', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const ProjectCard({
    Key? key,
    required this.project,
    required this.onTap,
    required this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                project.colore.withOpacity(0.8),
                project.colore,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.white70),
                  onPressed: onDelete,
                  iconSize: 20,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      project.icona,
                      size: 48,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      project.nome,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (project.descrizione.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        project.descrizione,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle, size: 16, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            '${project.taskCompletati}/${project.totaleTask}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: project.percentualeCompletamento / 100,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProjectDetailPage extends StatefulWidget {
  final Project project;
  final VoidCallback onChanged;

  const ProjectDetailPage({
    Key? key,
    required this.project,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  void _addTask(String titolo, String descrizione) {
    setState(() {
      widget.project.tasks.add(Task(titolo: titolo, descrizione: descrizione));
    });
    widget.onChanged(); // Salva i dati
  }

  void _updateTaskStatus(String taskId, TaskStatus newStatus) {
    setState(() {
      final task = widget.project.tasks.firstWhere((t) => t.id == taskId);
      task.status = newStatus;
    });
    widget.onChanged(); // Salva i dati
  }

  void _deleteTask(String taskId) {
    setState(() {
      widget.project.tasks.removeWhere((t) => t.id == taskId);
    });
    widget.onChanged(); // Salva i dati
  }

  void _showAddTaskDialog() {
    final titoloController = TextEditingController();
    final descrizioneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuovo Task'),
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
        title: Row(
          children: [
            Icon(widget.project.icona, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.project.nome,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: widget.project.colore,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.project.colore,
                  widget.project.colore.withOpacity(0.8),
                ],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (widget.project.descrizione.isNotEmpty)
                  Text(
                    widget.project.descrizione,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatCard(
                      label: 'Da fare',
                      value: widget.project.taskDaFare.toString(),
                      color: TaskStatus.daFare.color,
                    ),
                    _StatCard(
                      label: 'In corso',
                      value: widget.project.taskInCorso.toString(),
                      color: TaskStatus.inCorso.color,
                    ),
                    _StatCard(
                      label: 'Completati',
                      value: widget.project.taskCompletati.toString(),
                      color: TaskStatus.completato.color,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const StatusLegend(),
          Expanded(
            child: widget.project.tasks.isEmpty
                ? const EmptyTasksState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.project.tasks.length,
                    itemBuilder: (context, index) {
                      final task = widget.project.tasks[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TaskCard(
                          task: task,
                          onStatusChange: (status) => _updateTaskStatus(task.id, status),
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
        backgroundColor: widget.project.colore,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
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
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: task.status.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
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
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete, color: Colors.red),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
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
            const SizedBox(height: 8),
            Text(
              dateFormat.format(task.data),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w300,
              ),
            ),
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

class EmptyProjectsState extends StatelessWidget {
  const EmptyProjectsState({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Text('📁', style: TextStyle(fontSize: 64)),
          SizedBox(height: 16),
          Text(
            'Nessun progetto',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Crea il tuo primo progetto',
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

class EmptyTasksState extends StatelessWidget {
  const EmptyTasksState({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Text('📋', style: TextStyle(fontSize: 64)),
          SizedBox(height: 16),
          Text(
            'Nessun task in questo progetto',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Premi + per aggiungere un task',
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
