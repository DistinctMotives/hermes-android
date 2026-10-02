/// Hermes Project records exposed by the Gateway `projects.*` JSON-RPC family.
///
/// These mirror `hermes_cli/projects_db.py` (`Project.to_dict` and
/// `ProjectFolder.to_dict`) so Android reads the same server-owned workspace
/// Hermes Desktop reads, instead of a client-only organization store.
library;

/// One workspace folder attached to a [HermesProject].
class ProjectFolder {
  final String path;
  final String? label;
  final bool isPrimary;
  final int? addedAt;

  const ProjectFolder({
    required this.path,
    this.label,
    this.isPrimary = false,
    this.addedAt,
  });

  factory ProjectFolder.fromJson(Map<String, dynamic> json) {
    final path = _trimmedString(json['path']);
    if (path == null) {
      throw const FormatException('A project folder requires a path');
    }
    return ProjectFolder(
      path: path,
      label: _trimmedString(json['label']),
      isPrimary: json['is_primary'] == true,
      addedAt: _asInt(json['added_at']),
    );
  }
}

/// A server-owned Hermes Project: a named, multi-folder workspace.
class HermesProject {
  final String id;
  final String slug;
  final String name;
  final String? description;
  final String? icon;
  final String? color;
  final String? boardSlug;
  final String? primaryPath;
  final bool archived;
  final int? createdAt;
  final List<ProjectFolder> folders;

  const HermesProject({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    this.icon,
    this.color,
    this.boardSlug,
    this.primaryPath,
    this.archived = false,
    this.createdAt,
    this.folders = const [],
  });

  factory HermesProject.fromJson(Map<String, dynamic> json) {
    final id = _trimmedString(json['id']);
    if (id == null) {
      throw const FormatException('A project record requires an id');
    }
    final name = _trimmedString(json['name']) ?? id;
    final rawFolders = json['folders'];
    return HermesProject(
      id: id,
      slug: _trimmedString(json['slug']) ?? id,
      name: name,
      description: _trimmedString(json['description']),
      icon: _trimmedString(json['icon']),
      color: _trimmedString(json['color']),
      boardSlug: _trimmedString(json['board_slug']),
      primaryPath: _trimmedString(json['primary_path']),
      archived: json['archived'] == true,
      createdAt: _asInt(json['created_at']),
      folders: rawFolders is List
          ? rawFolders
                .whereType<Map>()
                .map(
                  (folder) =>
                      ProjectFolder.fromJson(Map<String, dynamic>.from(folder)),
                )
                .toList(growable: false)
          : const [],
    );
  }

  /// The folder Hermes treats as this project's working directory, when known.
  String? get workingDirectory {
    if (primaryPath != null) return primaryPath;
    for (final folder in folders) {
      if (folder.isPrimary) return folder.path;
    }
    return folders.isEmpty ? null : folders.first.path;
  }
}

/// The full `projects.list` payload: every project plus the selected one.
class ProjectsSnapshot {
  final List<HermesProject> projects;

  /// The gateway's active project, or `null` when nothing is selected or the
  /// reported id no longer resolves to a known project.
  final String? activeId;

  const ProjectsSnapshot({required this.projects, this.activeId});

  factory ProjectsSnapshot.fromJson(Map<String, dynamic> json) {
    final rawProjects = json['projects'];
    final projects = rawProjects is List
        ? rawProjects
              .whereType<Map>()
              .map(
                (project) =>
                    HermesProject.fromJson(Map<String, dynamic>.from(project)),
              )
              .toList(growable: false)
        : const <HermesProject>[];
    final rawActiveId = _trimmedString(json['active_id']);
    final activeId = projects.any((project) => project.id == rawActiveId)
        ? rawActiveId
        : null;
    return ProjectsSnapshot(projects: projects, activeId: activeId);
  }

  static const empty = ProjectsSnapshot(projects: []);

  List<HermesProject> get active =>
      projects.where((project) => !project.archived).toList(growable: false);

  List<HermesProject> get archived =>
      projects.where((project) => project.archived).toList(growable: false);

  HermesProject? get activeProject {
    final id = activeId;
    if (id == null) return null;
    for (final project in projects) {
      if (project.id == id) return project;
    }
    return null;
  }
}

String? _trimmedString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}
