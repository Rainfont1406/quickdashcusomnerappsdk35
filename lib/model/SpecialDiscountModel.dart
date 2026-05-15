class SpecialDiscountModel {
  String? day;
  List<Timeslot>? timeslot;

  SpecialDiscountModel({this.day, this.timeslot});

  SpecialDiscountModel.fromJson(Map<String, dynamic> json) {
    day = json['day'];
    if (json['timeslot'] != null) {
      timeslot = <Timeslot>[];
      json['timeslot'].forEach((v) {
        timeslot!.add(Timeslot.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['day'] = day;
    if (timeslot != null) {
      data['timeslot'] = timeslot!.map((v) => v.toJson()).toList();
    }
    return data;
  }
}

class Timeslot {
  String? from;
  String? to;
  String? discount;
  String? type;
  String? discount_type;
  String? applicableAmount;
  String? orderType;

  Timeslot({this.from, this.to, this.discount, this.type, this.applicableAmount, this.orderType});

  Timeslot.fromJson(Map<String, dynamic> json) {
    from = json['from'];
    to = json['to'];
    discount = json['discount'];
    type = json['type'];
    discount_type = json['discount_type'];
    applicableAmount = json['applicableAmount'];
    orderType = json['orderType'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['from'] = from;
    data['to'] = to;
    data['discount'] = discount;
    data['type'] = type;
    data['discount_type'] = discount_type;
    data['applicableAmount'] = applicableAmount;
    data['orderType'] = orderType;
    return data;
  }
}
