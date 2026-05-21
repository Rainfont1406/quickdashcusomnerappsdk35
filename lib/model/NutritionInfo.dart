class NutritionInfo {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;

  const NutritionInfo({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
  });

  factory NutritionInfo.fromJson(Map<String, dynamic> json) => NutritionInfo(
        calories: (json['calories'] as num?)?.toDouble() ?? 0,
        protein: (json['protein'] as num?)?.toDouble() ?? 0,
        carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
        fat: (json['fat'] as num?)?.toDouble() ?? 0,
        fiber: (json['fiber'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'fiber': fiber,
      };

  NutritionInfo copyWith({
    double? calories,
    double? protein,
    double? carbs,
    double? fat,
    double? fiber,
  }) =>
      NutritionInfo(
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fat: fat ?? this.fat,
        fiber: fiber ?? this.fiber,
      );

  static String classifyCalories(double v) =>
      v < 250 ? 'Low' : v <= 500 ? 'Medium' : 'High';
  static String classifyProtein(double v) =>
      v < 10 ? 'Low' : v <= 20 ? 'Medium' : 'High';
  static String classifyCarbs(double v) =>
      v < 20 ? 'Low' : v <= 40 ? 'Medium' : 'High';
  static String classifyFat(double v) =>
      v < 10 ? 'Low' : v <= 20 ? 'Medium' : 'High';
  static String classifyFiber(double v) =>
      v < 3 ? 'Low' : v <= 6 ? 'Medium' : 'High';

  String classifyMetric(String metric) {
    switch (metric) {
      case 'Calories':
        return classifyCalories(calories);
      case 'Protein':
        return classifyProtein(protein);
      case 'Carbs':
        return classifyCarbs(carbs);
      case 'Fat':
        return classifyFat(fat);
      case 'Fiber':
        return classifyFiber(fiber);
      default:
        return 'Low';
    }
  }

  List<Map<String, String>> getHighlights() {
    final highlights = <Map<String, String>>[];
    if (classifyCalories(calories) == 'High') {
      highlights.add({'metric': 'Calories', 'value': calories.toStringAsFixed(0), 'unit': 'kcal'});
    }
    if (classifyProtein(protein) == 'High') {
      highlights.add({'metric': 'Protein', 'value': protein.toStringAsFixed(0), 'unit': 'g'});
    }
    if (classifyCarbs(carbs) == 'High') {
      highlights.add({'metric': 'Carbs', 'value': carbs.toStringAsFixed(0), 'unit': 'g'});
    }
    if (classifyFat(fat) == 'High') {
      highlights.add({'metric': 'Fat', 'value': fat.toStringAsFixed(0), 'unit': 'g'});
    }
    if (classifyFiber(fiber) == 'High') {
      highlights.add({'metric': 'Fiber', 'value': fiber.toStringAsFixed(0), 'unit': 'g'});
    }
    return highlights;
  }
}
