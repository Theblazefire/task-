import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';

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

  static TaskStatus fromString(String status) {
    return TaskStatus.values.firstWhere(
      (e) => e.name == status,
      orElse: () => TaskStatus.daFare,
    );
  }
}

// Modello per un Task (ora con sub-task infiniti!)
class Task {
  final String id;
  final String titolo;
  final String descrizione;
  final DateTime data;
  TaskStatus status;
  final List<Task> subtasks; // ← SUB-TASK RICORSIVI!

  Task({
    String? id,
    required this.titolo,
    this.descrizione = '',
    DateTime? data,
    this.status = TaskStatus.daFare,
    List<Task>? subtasks,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        data = data ?? DateTime.now(),
        subtasks = subtasks ?? [];

  // Conta task totali (inclusi sub-task) RICORSIVAMENTE
  int get totaleTaskConSubtask {
    int count = 1; // Questo task
    for (var subtask in subtasks) {
      count += subtask.totaleTaskConSubtask; // Ricorsione!
    }
    return count;
  }

  // Conta sub-task completati RICORSIVAMENTE
  int get subtaskCompletati {
    int count = status == TaskStatus.completato ? 1 : 0;
    for (var subtask in subtasks) {
      count += subtask.subtaskCompletati;
    }
    return count;
  }

  // Ha sub-task?
  bool get hasSubtasks => subtasks.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'titolo': titolo,
      'descrizione': descrizione,
      'data': data.toIso8601String(),
      'status': status.name,
      'subtasks': subtasks.map((t) => t.toJson()).toList(), // Ricorsivo!
    };
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'],
      titolo: json['titolo'],
      descrizione: json['descrizione'] ?? '',
      data: DateTime.parse(json['data']),
      status: TaskStatus.fromString(json['status']),
      subtasks: (json['subtasks'] as List?)
              ?.map((t) => Task.fromJson(t)) // Ricorsivo!
              .toList() ??
          [],
    );
  }
}

// NUOVO: Modello per una Sezione (sotto-progetto)
class Section {
  final String id;
  final String nome;
  final String descrizione;
  final IconData icona;
  final List<Task> tasks;

  Section({
    String? id,
    required this.nome,
    this.descrizione = '',
    this.icona = Icons.folder_outlined,
    List<Task>? tasks,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        tasks = tasks ?? [];

  int get totaleTask => tasks.length;
  int get taskCompletati =>
      tasks.where((t) => t.status == TaskStatus.completato).length;
  int get taskInCorso =>
      tasks.where((t) => t.status == TaskStatus.inCorso).length;
  int get taskDaFare =>
      tasks.where((t) => t.status == TaskStatus.daFare).length;
  double get percentualeCompletamento =>
      totaleTask > 0 ? (taskCompletati / totaleTask * 100) : 0;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'descrizione': descrizione,
      'icona': icona.codePoint,
      'tasks': tasks.map((t) => t.toJson()).toList(),
    };
  }

  factory Section.fromJson(Map<String, dynamic> json) {
    return Section(
      id: json['id'],
      nome: json['nome'],
      descrizione: json['descrizione'] ?? '',
      icona: IconData(json['icona'], fontFamily: 'MaterialIcons'),
      tasks:
          (json['tasks'] as List?)?.map((t) => Task.fromJson(t)).toList() ?? [],
    );
  }
}

// Modello per un Progetto (ora con sezioni)
class Project {
  final String id;
  final String nome;
  final String descrizione;
  final Color colore;
  final IconData icona;
  final DateTime dataCreazione;
  final List<Section> sections;

  Project({
    String? id,
    required this.nome,
    this.descrizione = '',
    this.colore = Colors.blue,
    this.icona = Icons.folder,
    DateTime? dataCreazione,
    List<Section>? sections,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        dataCreazione = dataCreazione ?? DateTime.now(),
        sections = sections ?? [];

  int get totaleTask => sections.fold(0, (sum, s) => sum + s.totaleTask);
  int get taskCompletati =>
      sections.fold(0, (sum, s) => sum + s.taskCompletati);
  int get taskInCorso => sections.fold(0, (sum, s) => sum + s.taskInCorso);
  int get taskDaFare => sections.fold(0, (sum, s) => sum + s.taskDaFare);
  double get percentualeCompletamento =>
      totaleTask > 0 ? (taskCompletati / totaleTask * 100) : 0;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'descrizione': descrizione,
      'colore': colore.value,
      'icona': icona.codePoint,
      'dataCreazione': dataCreazione.toIso8601String(),
      'sections': sections.map((s) => s.toJson()).toList(),
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      nome: json['nome'],
      descrizione: json['descrizione'] ?? '',
      colore: Color(json['colore']),
      icona: IconData(json['icona'], fontFamily: 'MaterialIcons'),
      dataCreazione: DateTime.parse(json['dataCreazione']),
      sections: (json['sections'] as List?)
              ?.map((s) => Section.fromJson(s))
              .toList() ??
          [],
    );
  }
}

// Servizio di storage
class StorageService {
  static const String _keyProjects = 'projects_data';

  static Future<void> saveProjects(List<Project> projects) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = projects.map((p) => p.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await prefs.setString(_keyProjects, jsonString);
    print('💾 Salvati ${projects.length} progetti');
  }

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

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyProjects);
    print('🗑️ Tutti i dati cancellati');
  }

  // ============================================
  // GESTIONE PERMESSI
  // ============================================

  /// Verifica e richiede permessi storage
  static Future<bool> requestStoragePermission() async {
    if (kIsWeb) return true;

    if (!Platform.isAndroid) {
      return true; // iOS non ha bisogno
    }

    try {
      // Android 13+ (API 33+) - Non serve permesso per Download
      if (Platform.version.contains('33') ||
          Platform.version.contains('34') ||
          Platform.version.contains('35')) {
        return true;
      }

      // Android 11-12 (API 30-32)
      var status = await Permission.storage.status;
      if (status.isGranted) {
        return true;
      }

      // Richiedi permesso
      status = await Permission.storage.request();

      if (status.isPermanentlyDenied) {
        // Utente ha negato permanentemente
        print('⚠️ Permesso negato permanentemente');
        await openAppSettings();
        return false;
      }

      return status.isGranted;
    } catch (e) {
      print('❌ Errore permessi: $e');
      // Se c'è errore, proviamo comunque (potrebbe funzionare)
      return true;
    }
  }

  /// Ottieni cartella Download (accessibile senza permessi su Android 10+)
  static Future<Directory> getDownloadsDirectory() async {
    if (kIsWeb) {
      // Web: no filesystem access
      throw UnsupportedError('getDownloadsDirectory is not supported on web');
    }

    if (Platform.isAndroid) {
      // Cartella Download pubblica (sempre accessibile)
      return Directory('/storage/emulated/0/Download');
    } else {
      // iOS: usa Documents
      return await getApplicationDocumentsDirectory();
    }
  }

  // ============================================
  // EXPORT / IMPORT CON PERMESSI
  // ============================================

  /// Esporta UN progetto in formato JSON
  static Future<String?> exportProject(Project project) async {
    try {
      // Ottieni cartella Download
      final directory = await getDownloadsDirectory();

      // Crea directory se non esiste
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename =
          'progetto_${project.nome.replaceAll(' ', '_')}_$timestamp.json';
      final file = File('${directory.path}/$filename');

      final jsonData = {
        'version': '1.0',
        'exportDate': DateTime.now().toIso8601String(),
        'appName': 'Diario Checklist',
        'project': project.toJson(),
      };

      final jsonString = JsonEncoder.withIndent('  ').convert(jsonData);
      await file.writeAsString(jsonString);

      print('📤 Progetto esportato: ${file.path}');
      return file.path;
    } catch (e, stackTrace) {
      print('❌ Errore export: $e');
      print('Stack: $stackTrace');
      return null;
    }
  }

  /// Esporta TUTTI i progetti in formato JSON
  static Future<String?> exportAllProjects(List<Project> projects) async {
    try {
      // Ottieni cartella Download
      final directory = await getDownloadsDirectory();

      // Crea directory se non esiste
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'backup_completo_$timestamp.json';
      final file = File('${directory.path}/$filename');

      final jsonData = {
        'version': '1.0',
        'exportDate': DateTime.now().toIso8601String(),
        'appName': 'Diario Checklist',
        'projectCount': projects.length,
        'projects': projects.map((p) => p.toJson()).toList(),
      };

      final jsonString = JsonEncoder.withIndent('  ').convert(jsonData);
      await file.writeAsString(jsonString);

      print('📤 Backup completo esportato: ${file.path}');
      return file.path;
    } catch (e, stackTrace) {
      print('❌ Errore export completo: $e');
      print('Stack: $stackTrace');
      return null;
    }
  }

  /// Importa progetto da file JSON
  static Future<Project?> importProject(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('❌ File non trovato: $filePath');
        return null;
      }

      final jsonString = await file.readAsString();
      final jsonData = jsonDecode(jsonString);

      // Verifica formato
      if (jsonData['appName'] != 'Diario Checklist') {
        print('❌ File non valido (app diversa)');
        return null;
      }

      // Importa progetto singolo
      if (jsonData.containsKey('project')) {
        final project = Project.fromJson(jsonData['project']);
        print('📥 Progetto importato: ${project.nome}');
        return project;
      }

      print('❌ Formato file non valido');
      return null;
    } catch (e, stackTrace) {
      print('❌ Errore import: $e');
      print('Stack: $stackTrace');
      return null;
    }
  }

  /// Importa backup completo (tutti i progetti)
  static Future<List<Project>?> importAllProjects(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('❌ File non trovato: $filePath');
        return null;
      }

      final jsonString = await file.readAsString();
      final jsonData = jsonDecode(jsonString);

      // Verifica formato
      if (jsonData['appName'] != 'Diario Checklist') {
        print('❌ File non valido (app diversa)');
        return null;
      }

      // Importa progetti multipli
      if (jsonData.containsKey('projects')) {
        final projects = (jsonData['projects'] as List)
            .map((json) => Project.fromJson(json))
            .toList();
        print('📥 Importati ${projects.length} progetti');
        return projects;
      }

      print('❌ Formato file non valido');
      return null;
    } catch (e, stackTrace) {
      print('❌ Errore import completo: $e');
      print('Stack: $stackTrace');
      return null;
    }
  }

  /// Condividi file esportato
  static Future<void> shareFile(String filePath, String filename) async {
    try {
      final file = XFile(filePath);
      await Share.shareXFiles(
        [file],
        subject: 'Backup Diario Checklist',
        text: 'Ecco il backup dei miei progetti!',
      );
      print('📤 File condiviso: $filename');
    } catch (e) {
      print('❌ Errore condivisione: $e');
    }
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

// Home Page con lista progetti
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

  Future<void> _loadData() async {
    final projects = await StorageService.loadProjects();
    setState(() {
      _projects = projects;
      _isLoading = false;
    });
  }

  Future<void> _saveData() async {
    await StorageService.saveProjects(_projects);
  }

  void _addProject(
      String nome, String descrizione, Color colore, IconData icona) {
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

  // ============================================
  // EXPORT / IMPORT
  // ============================================

  Future<void> _exportAllProjects() async {
    if (_projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessun progetto da esportare')),
      );
      return;
    }

    final filePath = await StorageService.exportAllProjects(_projects);
    if (filePath != null) {
      // Mostra dialog con opzioni
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('✅ Backup Creato!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Esportati ${_projects.length} progetti'),
              const SizedBox(height: 8),
              const Text(
                'Scegli cosa fare:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Chiudi'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await StorageService.shareFile(
                  filePath,
                  filePath.split('/').last,
                );
              },
              icon: const Icon(Icons.share),
              label: const Text('Condividi'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Errore durante l\'esportazione')),
      );
    }
  }

  Future<void> _importProjects() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) {
        return; // Utente ha annullato
      }

      final filePath = result.files.single.path!;

      // Prova a importare come backup completo
      final importedProjects = await StorageService.importAllProjects(filePath);

      if (importedProjects != null && importedProjects.isNotEmpty) {
        // Chiedi conferma
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Importa Progetti'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Trovati ${importedProjects.length} progetti:'),
                const SizedBox(height: 8),
                ...importedProjects.take(5).map((p) => Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 4),
                      child: Row(
                        children: [
                          Icon(p.icona, size: 16, color: p.colore),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              p.nome,
                              style: const TextStyle(fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )),
                if (importedProjects.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text(
                      '... e altri ${importedProjects.length - 5}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Come vuoi importarli?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('Aggiungi'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, null),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Sostituisci'),
              ),
            ],
          ),
        );

        if (confirm == true) {
          // Aggiungi ai progetti esistenti
          setState(() {
            _projects.addAll(importedProjects);
          });
          await _saveData();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Aggiunti ${importedProjects.length} progetti'),
            ),
          );
        } else if (confirm == null) {
          // Sostituisci tutti
          setState(() {
            _projects = importedProjects;
          });
          await _saveData();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Importati ${importedProjects.length} progetti'),
            ),
          );
        }
      } else {
        // Prova a importare come progetto singolo
        final project = await StorageService.importProject(filePath);
        if (project != null) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Importa Progetto'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(project.icona, color: project.colore),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          project.nome,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${project.sections.length} sezioni, ${project.totaleTask} task',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Importa'),
                ),
              ],
            ),
          );

          if (confirm == true) {
            setState(() {
              _projects.add(project);
            });
            await _saveData();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('✅ Progetto "${project.nome}" importato')),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ File non valido')),
          );
        }
      }
    } catch (e) {
      print('Errore import: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Errore durante l\'importazione')),
      );
    }
  }

  void _showExportImportMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.blue),
              title: const Text('Esporta Tutti i Progetti'),
              subtitle: Text('${_projects.length} progetti'),
              onTap: () {
                Navigator.pop(context);
                _exportAllProjects();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.green),
              title: const Text('Importa da File'),
              subtitle: const Text('Backup completo o progetto singolo'),
              onTap: () {
                Navigator.pop(context);
                _importProjects();
              },
            ),
          ],
        ),
      ),
    );
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
                const Text('Colore:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
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
                            color: selectedColor == color
                                ? Colors.black
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text('Icona:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
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
                          color: selectedIcon == icon
                              ? Colors.grey.shade300
                              : Colors.transparent,
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
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'I Miei Progetti',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Pulsante Import/Export
          IconButton(
            icon: const Icon(Icons.import_export),
            tooltip: 'Importa/Esporta',
            onPressed: _showExportImportMenu,
          ),
          // Pulsante Statistiche
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Statistiche',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => StatisticsPage(projects: _projects),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Cancella tutti i dati',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Conferma'),
                  content: const Text(
                      'Vuoi cancellare TUTTI i progetti? Questa azione non può essere annullata.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annulla'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style:
                          FilledButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Cancella Tutto'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await StorageService.clearAll();
                setState(() => _projects.clear());
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Tutti i dati sono stati cancellati')),
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
                    setState(() {});
                  },
                  onDelete: () => _deleteProject(project.id),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProjectDialog,
        backgroundColor: Theme.of(context).primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label:
            const Text('Nuovo Progetto', style: TextStyle(color: Colors.white)),
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
              colors: [project.colore.withOpacity(0.8), project.colore],
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
                    Icon(project.icona, size: 48, color: Colors.white),
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
                            fontSize: 12, color: Colors.white70),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const Spacer(),
                    // Mostra numero sezioni
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.folder_outlined,
                              size: 16, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            '${project.sections.length} sezioni',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle,
                              size: 16, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            '${project.taskCompletati}/${project.totaleTask} task',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11),
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
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
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

// NUOVA: Pagina dettaglio progetto con SEZIONI
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
  void _addSection(String nome, String descrizione, IconData icona) {
    setState(() {
      widget.project.sections.add(Section(
        nome: nome,
        descrizione: descrizione,
        icona: icona,
      ));
    });
    widget.onChanged();
  }

  void _deleteSection(String sectionId) {
    setState(() {
      widget.project.sections.removeWhere((s) => s.id == sectionId);
    });
    widget.onChanged();
  }

  void _showAddSectionDialog() {
    final nomeController = TextEditingController();
    final descrizioneController = TextEditingController();
    IconData selectedIcon = Icons.folder_outlined;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuova Sezione'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeController,
                decoration: const InputDecoration(
                  labelText: 'Nome Sezione *',
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
              const Text('Icona:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  Icons.folder_outlined,
                  Icons.list_alt,
                  Icons.check_box,
                  Icons.assignment,
                  Icons.note,
                  Icons.event,
                  Icons.star,
                  Icons.label,
                ].map((icon) {
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedIcon = icon),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: selectedIcon == icon
                            ? widget.project.colore.withOpacity(0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: widget.project.colore),
                    ),
                  );
                }).toList(),
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
                if (nomeController.text.trim().isNotEmpty) {
                  _addSection(
                    nomeController.text.trim(),
                    descrizioneController.text.trim(),
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
        actions: [
          // Pulsante Export Progetto
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Esporta questo progetto',
            onPressed: () async {
              final filePath =
                  await StorageService.exportProject(widget.project);
              if (filePath != null) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('✅ Progetto Esportato!'),
                    content: Text('File: ${filePath.split('/').last}'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                      FilledButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await StorageService.shareFile(
                            filePath,
                            filePath.split('/').last,
                          );
                        },
                        icon: const Icon(Icons.share),
                        label: const Text('Condividi'),
                      ),
                    ],
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('❌ Errore durante l\'esportazione')),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Header con statistiche
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
                      label: 'Sezioni',
                      value: widget.project.sections.length.toString(),
                      icon: Icons.folder_outlined,
                      color: widget.project.colore,
                    ),
                    _StatCard(
                      label: 'Task Totali',
                      value: widget.project.totaleTask.toString(),
                      icon: Icons.checklist,
                      color: widget.project.colore,
                    ),
                    _StatCard(
                      label: 'Completati',
                      value: widget.project.taskCompletati.toString(),
                      icon: Icons.check_circle,
                      color: TaskStatus.completato.color,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Lista sezioni
          Expanded(
            child: widget.project.sections.isEmpty
                ? const EmptySectionsState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.project.sections.length,
                    itemBuilder: (context, index) {
                      final section = widget.project.sections[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SectionCard(
                          section: section,
                          projectColor: widget.project.colore,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SectionDetailPage(
                                  section: section,
                                  projectColor: widget.project.colore,
                                  onChanged: widget.onChanged,
                                ),
                              ),
                            );
                            setState(() {});
                          },
                          onDelete: () => _deleteSection(section.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _buildDualFAB(),
    );
  }

  Widget _buildDualFAB() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Pulsante Nuova Sezione
          FloatingActionButton.extended(
            onPressed: _showAddSectionDialog,
            backgroundColor: widget.project.colore,
            heroTag: 'section',
            icon: const Icon(Icons.folder_outlined, color: Colors.white),
            label: const Text('Sezione', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 12),
          // Pulsante Nuovo Task Rapido
          FloatingActionButton.extended(
            onPressed: _showAddQuickTaskDialog,
            backgroundColor: widget.project.colore.withOpacity(0.8),
            heroTag: 'task',
            icon: const Icon(Icons.add_task, color: Colors.white),
            label: const Text('Task', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAddQuickTaskDialog() {
    final titoloController = TextEditingController();
    final descrizioneController = TextEditingController();
    Section? selectedSection;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuovo Task Rapido'),
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
              const SizedBox(height: 16),
              // Selettore sezione
              if (widget.project.sections.isNotEmpty) ...[
                const Text(
                  'Seleziona Sezione:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<Section>(
                    value: selectedSection,
                    isExpanded: true,
                    hint: const Text('Scegli una sezione'),
                    underline: const SizedBox(),
                    items: widget.project.sections.map((section) {
                      return DropdownMenuItem<Section>(
                        value: section,
                        child: Row(
                          children: [
                            Icon(section.icona,
                                size: 20, color: widget.project.colore),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                section.nome,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (Section? newValue) {
                      setDialogState(() {
                        selectedSection = newValue;
                      });
                    },
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.info_outline, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Crea prima una sezione!',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed:
                  widget.project.sections.isEmpty || selectedSection == null
                      ? null
                      : () {
                          if (titoloController.text.trim().isNotEmpty &&
                              selectedSection != null) {
                            setState(() {
                              selectedSection!.tasks.add(Task(
                                titolo: titoloController.text.trim(),
                                descrizione: descrizioneController.text.trim(),
                              ));
                            });
                            widget.onChanged();
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Task aggiunto a "${selectedSection!.nome}"'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
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
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// Card della sezione
class SectionCard extends StatelessWidget {
  final Section section;
  final Color projectColor;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const SectionCard({
    Key? key,
    required this.section,
    required this.projectColor,
    required this.onTap,
    required this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: projectColor, width: 2),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: projectColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(section.icona, color: projectColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.nome,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (section.descrizione.isNotEmpty)
                          Text(
                            section.descrizione,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: onDelete,
                    iconSize: 20,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _MiniStat(
                    icon: Icons.check_circle,
                    value: '${section.taskCompletati}/${section.totaleTask}',
                    color: TaskStatus.completato.color,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: section.percentualeCompletamento / 100,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(projectColor),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${section.percentualeCompletamento.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: projectColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

// NUOVA: Pagina dettaglio sezione con TASK
class SectionDetailPage extends StatefulWidget {
  final Section section;
  final Color projectColor;
  final VoidCallback onChanged;

  const SectionDetailPage({
    Key? key,
    required this.section,
    required this.projectColor,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<SectionDetailPage> createState() => _SectionDetailPageState();
}

class _SectionDetailPageState extends State<SectionDetailPage> {
  void _addTask(String titolo, String descrizione) {
    setState(() {
      widget.section.tasks.add(Task(titolo: titolo, descrizione: descrizione));
    });
    widget.onChanged();
  }

  void _updateTaskStatus(String taskId, TaskStatus newStatus) {
    setState(() {
      final task = widget.section.tasks.firstWhere((t) => t.id == taskId);
      task.status = newStatus;
    });
    widget.onChanged();
  }

  void _deleteTask(String taskId) {
    setState(() {
      widget.section.tasks.removeWhere((t) => t.id == taskId);
    });
    widget.onChanged();
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
            Icon(widget.section.icona, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.section.nome,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: widget.projectColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.projectColor,
                  widget.projectColor.withOpacity(0.8),
                ],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (widget.section.descrizione.isNotEmpty)
                  Text(
                    widget.section.descrizione,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatCard(
                      label: 'Da fare',
                      value: widget.section.taskDaFare.toString(),
                      icon: Icons.circle,
                      color: TaskStatus.daFare.color,
                    ),
                    _StatCard(
                      label: 'In corso',
                      value: widget.section.taskInCorso.toString(),
                      icon: Icons.circle,
                      color: TaskStatus.inCorso.color,
                    ),
                    _StatCard(
                      label: 'Completati',
                      value: widget.section.taskCompletati.toString(),
                      icon: Icons.check_circle,
                      color: TaskStatus.completato.color,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Legenda
          const StatusLegend(),

          // Lista task
          Expanded(
            child: widget.section.tasks.isEmpty
                ? const EmptyTasksState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.section.tasks.length,
                    itemBuilder: (context, index) {
                      final task = widget.section.tasks[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TaskCard(
                          task: task,
                          onStatusChange: (status) =>
                              _updateTaskStatus(task.id, status),
                          onDelete: () => _deleteTask(task.id),
                          onChanged: widget.onChanged, // Aggiungo callback
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskDialog,
        backgroundColor: widget.projectColor,
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
  final VoidCallback? onChanged; // Per aggiornare quando cambiano subtask

  const TaskCard({
    Key? key,
    required this.task,
    required this.onStatusChange,
    required this.onDelete,
    this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy, HH:mm');

    final textColor =
        task.status == TaskStatus.inCorso ? Colors.black : Colors.white;

    final deleteIconColor = task.status == TaskStatus.inCorso
        ? Colors.red.shade700
        : Colors.white70;

    return Card(
      elevation: 4,
      color: task.status.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: task.hasSubtasks
            ? () async {
                // Apri pagina subtask
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SubtaskPage(
                      task: task,
                      onChanged: onChanged,
                    ),
                  ),
                );
                if (onChanged != null) onChanged!();
              }
            : null,
        borderRadius: BorderRadius.circular(12),
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
                      color: textColor,
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
                        color: textColor,
                        decoration: task.status == TaskStatus.completato
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  // Badge subtask
                  if (task.hasSubtasks) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: textColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.subdirectory_arrow_right,
                            size: 14,
                            color: textColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${task.subtaskCompletati}/${task.totaleTaskConSubtask - 1}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    onPressed: onDelete,
                    icon: Icon(Icons.delete, color: deleteIconColor),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              if (task.descrizione.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  task.descrizione,
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor.withOpacity(0.9),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    dateFormat.format(task.data),
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor.withOpacity(0.8),
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  if (task.hasSubtasks) ...[
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: textColor.withOpacity(0.6),
                    ),
                  ],
                ],
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
              // Pulsante aggiungi subtask
              if (!task.hasSubtasks)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 36,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SubtaskPage(
                              task: task,
                              onChanged: onChanged,
                            ),
                          ),
                        );
                        if (onChanged != null) onChanged!();
                      },
                      icon: Icon(
                        Icons.add,
                        color: textColor,
                        size: 18,
                      ),
                      label: Text(
                        'Aggiungi Sub-Task',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 12,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: textColor.withOpacity(0.3)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
          backgroundColor:
              isSelected ? Colors.white : Colors.black.withOpacity(0.2),
          foregroundColor: isSelected ? status.color : Colors.white,
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

// ============================================
// PAGINA SUB-TASK (Gestione Task Ricorsivi)
// ============================================

class SubtaskPage extends StatefulWidget {
  final Task task;
  final VoidCallback? onChanged;

  const SubtaskPage({
    Key? key,
    required this.task,
    this.onChanged,
  }) : super(key: key);

  @override
  State<SubtaskPage> createState() => _SubtaskPageState();
}

class _SubtaskPageState extends State<SubtaskPage> {
  void _addSubtask(String titolo, String descrizione) {
    setState(() {
      widget.task.subtasks.add(Task(
        titolo: titolo,
        descrizione: descrizione,
      ));
    });
    if (widget.onChanged != null) widget.onChanged!();
  }

  void _updateSubtaskStatus(String subtaskId, TaskStatus newStatus) {
    setState(() {
      final subtask = _findTaskById(widget.task, subtaskId);
      if (subtask != null) {
        subtask.status = newStatus;
      }
    });
    if (widget.onChanged != null) widget.onChanged!();
  }

  void _deleteSubtask(String subtaskId) {
    setState(() {
      _removeTaskById(widget.task, subtaskId);
    });
    if (widget.onChanged != null) widget.onChanged!();
  }

  // Trova task ricorsivamente
  Task? _findTaskById(Task task, String id) {
    if (task.id == id) return task;
    for (var subtask in task.subtasks) {
      final found = _findTaskById(subtask, id);
      if (found != null) return found;
    }
    return null;
  }

  // Rimuovi task ricorsivamente
  bool _removeTaskById(Task task, String id) {
    final exists = task.subtasks.any((t) => t.id == id);
    task.subtasks.removeWhere((t) => t.id == id);

    if (exists) {
      return true;
    }

    for (var subtask in task.subtasks) {
      if (_removeTaskById(subtask, id)) return true;
    }

    return false;
  }

  void _showAddSubtaskDialog() {
    final titoloController = TextEditingController();
    final descrizioneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuovo Sub-Task'),
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
                _addSubtask(
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
            Icon(
              Icons.subdirectory_arrow_right,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.task.titolo,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: widget.task.status.color,
        foregroundColor: widget.task.status == TaskStatus.inCorso
            ? Colors.black
            : Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header task padre
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.task.status.color,
                  widget.task.status.color.withOpacity(0.8),
                ],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.task.descrizione.isNotEmpty)
                  Text(
                    widget.task.descrizione,
                    style: TextStyle(
                      color: widget.task.status == TaskStatus.inCorso
                          ? Colors.black87
                          : Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSubtaskStat(
                      'Totali',
                      '${widget.task.subtasks.length}',
                      Icons.checklist,
                      widget.task.status.color,
                    ),
                    _buildSubtaskStat(
                      'Completati',
                      '${widget.task.subtaskCompletati}',
                      Icons.check_circle,
                      TaskStatus.completato.color,
                    ),
                    _buildSubtaskStat(
                      'Livelli',
                      '${_getMaxDepth(widget.task)}',
                      Icons.layers,
                      widget.task.status.color,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Lista subtask
          Expanded(
            child: widget.task.subtasks.isEmpty
                ? const EmptySubtasksState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.task.subtasks.length,
                    itemBuilder: (context, index) {
                      final subtask = widget.task.subtasks[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TaskCard(
                          task: subtask,
                          onStatusChange: (status) =>
                              _updateSubtaskStatus(subtask.id, status),
                          onDelete: () => _deleteSubtask(subtask.id),
                          onChanged: () => setState(() {}),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSubtaskDialog,
        backgroundColor: widget.task.status.color,
        child: Icon(
          Icons.add,
          color: widget.task.status == TaskStatus.inCorso
              ? Colors.black
              : Colors.white,
        ),
      ),
    );
  }

  Widget _buildSubtaskStat(
      String label, String value, IconData icon, Color color) {
    final textColor =
        widget.task.status == TaskStatus.inCorso ? Colors.black : Colors.white;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(
          widget.task.status == TaskStatus.inCorso ? 0.9 : 0.2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: widget.task.status == TaskStatus.inCorso ? color : textColor,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: widget.task.status == TaskStatus.inCorso
                  ? Colors.black87
                  : textColor,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: widget.task.status == TaskStatus.inCorso
                  ? Colors.black54
                  : textColor.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  // Calcola profondità massima dell'albero
  int _getMaxDepth(Task task) {
    if (task.subtasks.isEmpty) return 1;
    int maxSubDepth = 0;
    for (var subtask in task.subtasks) {
      int depth = _getMaxDepth(subtask);
      if (depth > maxSubDepth) maxSubDepth = depth;
    }
    return maxSubDepth + 1;
  }
}

class EmptySubtasksState extends StatelessWidget {
  const EmptySubtasksState({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Text('📝', style: TextStyle(fontSize: 64)),
          SizedBox(height: 16),
          Text(
            'Nessun sub-task',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Premi + per aggiungere un sub-task',
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

/*class EmptyProjectsState extends StatelessWidget {
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
}*/

class EmptySectionsState extends StatelessWidget {
  const EmptySectionsState({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Text('📂', style: TextStyle(fontSize: 64)),
          SizedBox(height: 16),
          Text(
            'Nessuna sezione in questo progetto',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Premi + per aggiungere una sezione',
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
            'Nessun task in questa sezione',
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
// ============================================
// PAGINA STATISTICHE - AGGIUNGI ALLA FINE DI main.dart
// ============================================

class StatisticsPage extends StatefulWidget {
  final List<Project> projects;

  const StatisticsPage({Key? key, required this.projects}) : super(key: key);

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  int _selectedProjectIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.projects.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Statistiche'),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('Nessun progetto da visualizzare'),
        ),
      );
    }

    final selectedProject = widget.projects[_selectedProjectIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Statistiche Progetti',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Selettore progetto
          Container(
            width: double.infinity,
            color: Colors.deepPurple,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Seleziona Progetto:',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<int>(
                    value: _selectedProjectIndex,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: List.generate(widget.projects.length, (index) {
                      final project = widget.projects[index];
                      return DropdownMenuItem<int>(
                        value: index,
                        child: Row(
                          children: [
                            Icon(project.icona,
                                color: project.colore, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                project.nome,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    onChanged: (int? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedProjectIndex = newValue;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          // Statistiche e grafici
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card riepilogo
                  _buildSummaryCard(selectedProject),
                  const SizedBox(height: 24),

                  // Grafico a torta - Status dei task
                  _buildSectionTitle('Distribuzione Stati'),
                  const SizedBox(height: 16),
                  _buildPieChart(selectedProject),
                  const SizedBox(height: 32),

                  // Grafico a barre - Task per sezione
                  _buildSectionTitle('Task per Sezione'),
                  const SizedBox(height: 16),
                  _buildBarChart(selectedProject),
                  const SizedBox(height: 32),

                  // Lista sezioni con dettagli
                  _buildSectionTitle('Dettaglio Sezioni'),
                  const SizedBox(height: 16),
                  ...selectedProject.sections.map((section) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildSectionDetailCard(
                          section, selectedProject.colore),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildSummaryCard(Project project) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [project.colore, project.colore.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(project.icona, size: 40, color: Colors.white),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.nome,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (project.descrizione.isNotEmpty)
                        Text(
                          project.descrizione,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  '${project.sections.length}',
                  'Sezioni',
                  Icons.folder_outlined,
                ),
                _buildStatItem(
                  '${project.totaleTask}',
                  'Task Totali',
                  Icons.checklist,
                ),
                _buildStatItem(
                  '${project.taskCompletati}',
                  'Completati',
                  Icons.check_circle,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: project.percentualeCompletamento / 100,
                minHeight: 12,
                backgroundColor: Colors.white.withOpacity(0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${project.percentualeCompletamento.toStringAsFixed(1)}% Completato',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildPieChart(Project project) {
    final daFare = project.taskDaFare;
    final inCorso = project.taskInCorso;
    final completati = project.taskCompletati;

    if (project.totaleTask == 0) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text('Nessun task presente'),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 250,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: [
                if (daFare > 0)
                  PieChartSectionData(
                    value: daFare.toDouble(),
                    title: '$daFare',
                    color: TaskStatus.daFare.color,
                    radius: 80,
                    titleStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                if (inCorso > 0)
                  PieChartSectionData(
                    value: inCorso.toDouble(),
                    title: '$inCorso',
                    color: TaskStatus.inCorso.color,
                    radius: 80,
                    titleStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                if (completati > 0)
                  PieChartSectionData(
                    value: completati.toDouble(),
                    title: '$completati',
                    color: TaskStatus.completato.color,
                    radius: 80,
                    titleStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart(Project project) {
    if (project.sections.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text('Nessuna sezione presente'),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 300,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: project.sections
                      .map((s) => s.totaleTask.toDouble())
                      .reduce((a, b) => a > b ? a : b) +
                  5,
              barTouchData: BarTouchData(enabled: true),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value.toInt() >= 0 &&
                          value.toInt() < project.sections.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            project.sections[value.toInt()].nome,
                            style: const TextStyle(fontSize: 10),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return const Text('');
                    },
                    reservedSize: 40,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 12),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(
                project.sections.length,
                (index) {
                  final section = project.sections[index];
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: section.totaleTask.toDouble(),
                        color: project.colore,
                        width: 20,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionDetailCard(Section section, Color projectColor) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(section.icona, color: projectColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.nome,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: projectColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${section.taskCompletati}/${section.totaleTask}',
                    style: TextStyle(
                      color: projectColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildMiniIndicator(
                  TaskStatus.daFare.color,
                  '${section.taskDaFare} Da fare',
                ),
                const SizedBox(width: 16),
                _buildMiniIndicator(
                  TaskStatus.inCorso.color,
                  '${section.taskInCorso} In corso',
                ),
                const SizedBox(width: 16),
                _buildMiniIndicator(
                  TaskStatus.completato.color,
                  '${section.taskCompletati} Completati',
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: section.percentualeCompletamento / 100,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(projectColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniIndicator(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }
}
