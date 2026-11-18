import 'dart:convert';

class ScenarioItem {
  final String id;
  final String name;
  final String description;
  final bool enabled;
  final List<ScenarioStep> steps;

  ScenarioItem({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
    required this.steps,
  });

  factory ScenarioItem.fromJson(Map<String, dynamic> json) {
    return ScenarioItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      steps: (json['steps'] as List<dynamic>?)
              ?.map((e) => ScenarioStep.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'enabled': enabled,
      'steps': steps.map((e) => e.toJson()).toList(),
    };
  }
}

class ScenarioStep {
  final String id;
  final String type;
  final String value;
  final int waitMs;

  ScenarioStep({
    required this.id,
    required this.type,
    required this.value,
    this.waitMs = 1000,
  });

  factory ScenarioStep.fromJson(Map<String, dynamic> json) {
    return ScenarioStep(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      value: json['value'] as String? ?? '',
      waitMs: json['waitMs'] as int? ?? 1000,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'value': value,
      'waitMs': waitMs,
    };
  }
}
