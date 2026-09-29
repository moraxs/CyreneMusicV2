/// 一笔支付订单（对应后端 `/member/orders` 的 `orders` 单项，数据源是 donations 集合）。
///
/// 后端 `payment_type` 一词两用（历史包袱，见 routes/card.ts 的 grantEntitlement）：
/// 既是业务类型（`card` = Cyrene Premium 买断、`manual` = 管理端补录），也承载
/// 赞助时客户端传的支付渠道（`alipay` / `wxpay`）。这里保留原始值，只在 UI 层
/// 派生展示名（[title]），不在客户端「修正」后端语义。
class PaymentOrder {
  const PaymentOrder({
    required this.id,
    required this.outTradeNo,
    required this.tradeNo,
    required this.amount,
    required this.paymentType,
    required this.paid,
    required this.paidAt,
    required this.createdAt,
  });

  final int id;

  /// 商户订单号：下单时由服务端生成，客服对账用，可复制。
  final String outTradeNo;

  /// 支付平台流水号：网关回调成功后回写，未支付时为空。
  final String? tradeNo;

  /// 订单金额（元）。
  final double amount;

  /// 后端原始 payment_type。
  final String paymentType;

  /// 是否已支付（后端 status==1）。
  final bool paid;

  /// 支付成功时间（ISO 8601，未支付为 null）。
  final String? paidAt;

  /// 下单时间（ISO 8601）。
  final String createdAt;

  /// 订单展示名。Premium 与「赞助」是两类东西，混在一句里用户会以为赞助买了会员。
  String get title {
    switch (paymentType) {
      case 'card':
        return 'Cyrene Premium';
      case 'alipay':
        return '支付宝赞助';
      case 'wxpay':
        return '微信赞助';
      case 'manual':
        return '赞助记录（管理员）';
      default:
        return paymentType.isEmpty ? '赞助' : '赞助（$paymentType）';
    }
  }

  /// 状态文案：待支付订单也要出现在列表里——用户换了设备/重开 App 后，
  /// 唯一能看到「这笔还没付」的地方就是这里。
  String get statusLabel => paid ? '已支付' : '待支付';

  /// 有效时间：已支付按支付时间，未支付按下单时间。
  String? get displayTime => paid ? (paidAt ?? createdAt) : createdAt;

  factory PaymentOrder.fromJson(Map<String, Object?> json) => PaymentOrder(
    id: (json['id'] as num?)?.toInt() ?? 0,
    outTradeNo: json['outTradeNo']?.toString() ?? '',
    tradeNo: json['tradeNo']?.toString(),
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    paymentType: json['paymentType']?.toString() ?? '',
    paid: ((json['status'] as num?) ?? 0).toInt() == 1,
    paidAt: json['paidAt']?.toString(),
    createdAt: json['createdAt']?.toString() ?? '',
  );
}

/// 「我的订单」页数据：订单流水 + 汇总。
///
/// 汇总直接来自后端对同一份列表的统计，避免客户端自己再算一遍出现两个口径。
class MembershipOrders {
  const MembershipOrders({
    required this.orders,
    required this.totalPaid,
    required this.paidCount,
    required this.pendingCount,
  });

  /// 按下单时间倒序。
  final List<PaymentOrder> orders;

  /// 累计已支付金额（元）。
  final double totalPaid;

  final int paidCount;

  /// 未支付订单数：用户「付了钱却没到账」时最先要看的就是这几笔。
  final int pendingCount;

  int get orderCount => orders.length;

  bool get isEmpty => orders.isEmpty;

  factory MembershipOrders.fromJson(Map<String, Object?> json) {
    final list = json['orders'];
    final stats = json['stats'];
    final statsMap = stats is Map ? Map<String, Object?>.from(stats) : const {};
    return MembershipOrders(
      orders: (list is List)
          ? list
                .whereType<Map>()
                .map((e) => PaymentOrder.fromJson(Map<String, Object?>.from(e)))
                .toList(growable: false)
          : const <PaymentOrder>[],
      totalPaid: (statsMap['totalPaid'] as num?)?.toDouble() ?? 0,
      paidCount: (statsMap['paidCount'] as num?)?.toInt() ?? 0,
      pendingCount: (statsMap['pendingCount'] as num?)?.toInt() ?? 0,
    );
  }
}
