class AdminCommissionModel {
  int? commission;
  bool? enable;
  String? type;
  int? takeawayCommission;

  AdminCommissionModel(
      {this.commission, this.enable, this.type, this.takeawayCommission});

  AdminCommissionModel.fromJson(Map<String, dynamic> json) {
    commission = json['commission'];
    enable = json['enable'];
    type = json['type'];
    takeawayCommission = json['takeawayCommission'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['commission'] = this.commission;
    data['enable'] = this.enable;
    data['type'] = this.type;
    data['takeawayCommission'] = this.takeawayCommission;
    return data;
  }
}
