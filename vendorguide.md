# Vendor App Implementation Guide for Dineaway Feature

## Overview
This guide explains how to implement the Dineaway feature in the vendor app to display order types (Takeaway or Dining) for incoming orders.

## Changes Required in Vendor App

### 1. Order Model Updates
The `OrderModel` in the vendor app should include the new `orderType` field to receive the order type information from Firebase.

**Update the OrderModel class:**
```dart
class OrderModel {
  // ... existing fields
  String? orderType; // "Takeaway" or "Dining" for Dineaway feature

  OrderModel({
    // ... existing parameters
    this.orderType,
  });

  factory OrderModel.fromJson(Map<String, dynamic> parsedJson) {
    return OrderModel(
      // ... existing fields
      orderType: parsedJson["orderType"],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      // ... existing fields
      "orderType": this.orderType,
    };
  }
}
```

### 2. Order Display UI Updates
Update the order cards/items to prominently display the order type.

**Example implementation:**
```dart
Widget buildOrderTypeIndicator(String? orderType) {
  if (orderType == null) return Container();

  return Container(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: orderType == "Dining" ? Colors.orange.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: orderType == "Dining" ? Colors.orange : Colors.blue,
        width: 1,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          orderType == "Dining" ? Icons.restaurant : Icons.shopping_bag,
          size: 16,
          color: orderType == "Dining" ? Colors.orange : Colors.blue,
        ),
        SizedBox(width: 4),
        Text(
          orderType,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: orderType == "Dining" ? Colors.orange : Colors.blue,
          ),
        ),
      ],
    ),
  );
}
```

### 3. Order List Screen Updates
In your order list screen, add the order type indicator to each order item.

**Example:**
```dart
Widget buildOrderCard(OrderModel order) {
  return Card(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order header with order type
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Order #${order.id}",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              buildOrderTypeIndicator(order.orderType),
            ],
          ),
          SizedBox(height: 8),

          // Order type description
          if (order.orderType != null)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                order.orderType == "Dining"
                  ? "🍽️ Customer will dine in the restaurant"
                  : "📦 Customer will take food to go",
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
            ),

          // ... rest of order details
        ],
      ),
    ),
  );
}
```

### 4. Order Details Screen Updates
In the detailed order view, make the order type very prominent.

**Example:**
```dart
Widget buildOrderTypeSection(String? orderType) {
  if (orderType == null) return Container();

  return Container(
    width: double.infinity,
    margin: EdgeInsets.symmetric(vertical: 16),
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: orderType == "Dining" ? Colors.orange[50] : Colors.blue[50],
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: orderType == "Dining" ? Colors.orange : Colors.blue,
        width: 2,
      ),
    ),
    child: Column(
      children: [
        Icon(
          orderType == "Dining" ? Icons.restaurant_menu : Icons.shopping_bag,
          size: 48,
          color: orderType == "Dining" ? Colors.orange : Colors.blue,
        ),
        SizedBox(height: 8),
        Text(
          orderType.toUpperCase(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: orderType == "Dining" ? Colors.orange : Colors.blue,
          ),
        ),
        SizedBox(height: 4),
        Text(
          orderType == "Dining"
            ? "Customer will eat inside the restaurant"
            : "Customer wants to pack the food for takeout",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
      ],
    ),
  );
}
```

### 5. Dashboard/Analytics Updates (Optional)
Consider adding order type analytics to help vendors understand their business patterns.

**Example metrics:**
```dart
Widget buildOrderTypeStats() {
  return Row(
    children: [
      Expanded(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.restaurant, color: Colors.orange),
                Text("Dining", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("${diningOrdersCount}", style: TextStyle(fontSize: 24)),
              ],
            ),
          ),
        ),
      ),
      SizedBox(width: 8),
      Expanded(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.shopping_bag, color: Colors.blue),
                Text("Takeaway", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("${takeawayOrdersCount}", style: TextStyle(fontSize: 24)),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
```

### 6. Push Notifications Updates (Optional)
Update push notification content to include order type information.

**Example:**
```dart
String buildOrderNotificationTitle(OrderModel order) {
  String orderType = order.orderType ?? "Order";
  return "$orderType Order Received - #${order.id}";
}

String buildOrderNotificationBody(OrderModel order) {
  String baseMessage = "New order from ${order.author.firstName}";
  if (order.orderType == "Dining") {
    return "$baseMessage - Customer will dine in";
  } else if (order.orderType == "Takeaway") {
    return "$baseMessage - Customer wants takeaway";
  }
  return baseMessage;
}
```

## Implementation Checklist

### Backend/Model Changes
- [ ] Add `orderType` field to OrderModel class
- [ ] Update `fromJson()` method to parse orderType
- [ ] Update `toJson()` method to serialize orderType
- [ ] Test order creation and retrieval with new field

### UI Changes
- [ ] Create order type indicator widget
- [ ] Update order list items to show order type
- [ ] Update order details screen to prominently display order type
- [ ] Add visual distinction between Dining and Takeaway orders
- [ ] Test UI with both order types

### Optional Enhancements
- [ ] Add order type filtering in order list
- [ ] Implement order type analytics/stats
- [ ] Update push notifications to include order type
- [ ] Add order type to receipt/invoice generation

## Color Scheme Recommendations

### Dining Orders
- Primary Color: Orange (`#FF9800`)
- Background: Orange with 10% opacity (`#FF9800` with 0.1 alpha)
- Icon: `Icons.restaurant` or `Icons.restaurant_menu`

### Takeaway Orders
- Primary Color: Blue (`#2196F3`)
- Background: Blue with 10% opacity (`#2196F3` with 0.1 alpha)
- Icon: `Icons.shopping_bag` or `Icons.takeout_dining`

## Testing Notes

1. **Order Reception**: Verify that orders with orderType field are received correctly
2. **Backward Compatibility**: Ensure orders without orderType field (from older app versions) still work
3. **Visual Testing**: Test UI with both order types to ensure clear distinction
4. **Edge Cases**: Test with null/empty orderType values

## Support

For any issues or questions regarding this implementation, please contact the development team or refer to the main project documentation.