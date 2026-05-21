import 'package:uuid/uuid.dart';

class BookingSlotModel {
  String id;
  String startTime;
  String endTime;
  int maxCapacity;
  bool isEnabled;

  BookingSlotModel({
    String? id,
    this.startTime = '',
    this.endTime = '',
    this.maxCapacity = 20,
    this.isEnabled = true,
  }) : id = id ?? const Uuid().v4();

  factory BookingSlotModel.fromJson(Map<String, dynamic> json) {
    return BookingSlotModel(
      id: json['id'] as String? ?? const Uuid().v4(),
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
      maxCapacity: (json['maxCapacity'] is num) ? (json['maxCapacity'] as num).toInt() : 20,
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime,
    'endTime': endTime,
    'maxCapacity': maxCapacity,
    'isEnabled': isEnabled,
  };

  BookingSlotModel copyWith({
    String? id,
    String? startTime,
    String? endTime,
    int? maxCapacity,
    bool? isEnabled,
  }) =>
      BookingSlotModel(
        id: id ?? this.id,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        maxCapacity: maxCapacity ?? this.maxCapacity,
        isEnabled: isEnabled ?? this.isEnabled,
      );
}
