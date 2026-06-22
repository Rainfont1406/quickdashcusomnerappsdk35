import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double radius;

  const UserAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 24.0,
  });

  // Extract initials
  String getInitials(String name) {
    final names = name.trim().split(' ').where((s) => s.isNotEmpty).toList();
    if (names.isEmpty) return '?';
    if (names.length == 1) return names.first[0].toUpperCase();
    return (names[0][0] + names[1][0]).toUpperCase();
  }

  // Generate a color based on the name
  Color getColorFromName(String name) {
    final colors = [
      Colors.deepOrange.shade400,
      Colors.orange.shade300,
      Colors.green.shade400,
      Colors.blue.shade400,
      Colors.purple.shade400,
      Colors.teal.shade400,
      Colors.indigo.shade400,
      Colors.pink.shade300,
      Colors.brown.shade400,
    ];

    int hash = name.codeUnits.fold(0, (prev, char) => prev + char);
    return colors[hash % colors.length];
  }

  // Make a lighter version of a given color
  Color lighten(Color color, [double amount = 0.4]) {
    return Color.lerp(color, Colors.white, amount)!;
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = getColorFromName(name);
    final textColor = lighten(bgColor, 0.4); // Light text based on bg

    return CircleAvatar(
      radius: radius,
      backgroundColor: (imageUrl == null || imageUrl!.isEmpty)
          ? bgColor
          : Colors.transparent,
      backgroundImage: imageUrl != null && imageUrl!.isNotEmpty
          ? NetworkImage(imageUrl!)
          : null,
      child: (imageUrl == null || imageUrl!.isEmpty)
          ? Text(
        getInitials(name),
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.6,
        ),
      )
          : null,
    );
  }
}