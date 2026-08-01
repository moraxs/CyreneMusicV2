/// 赞助者条目（对应 Next.js demo/lib/services/sponsorService.ts 的 Sponsor）。
class Sponsor {
  const Sponsor({
    required this.id,
    required this.username,
    required this.avatarUrl,
    required this.sponsorSince,
  });

  final int id;
  final String username;
  final String? avatarUrl;
  final String? sponsorSince;

  factory Sponsor.fromJson(Map<String, Object?> json) => Sponsor(
    id: ((json['id'] as num?) ?? 0).toInt(),
    username: json['username']?.toString() ?? '',
    avatarUrl: json['avatarUrl']?.toString(),
    sponsorSince: json['sponsorSince']?.toString(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'username': username,
    'avatarUrl': avatarUrl,
    'sponsorSince': sponsorSince,
  };
}

/// 赞助墙列表响应（对应 Next.js SponsorListResponse）。
class SponsorListResponse {
  const SponsorListResponse({
    required this.enabled,
    required this.sponsors,
    required this.total,
  });

  final bool enabled;
  final List<Sponsor> sponsors;
  final int total;

  factory SponsorListResponse.fromJson(Map<String, Object?> json) =>
      SponsorListResponse(
        enabled: json['enabled'] == true,
        sponsors:
            (json['sponsors'] as List?)
                ?.whereType<Map>()
                .map((e) => Sponsor.fromJson(Map<String, Object?>.from(e)))
                .toList() ??
            const [],
        total: ((json['total'] as num?) ?? 0).toInt(),
      );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'sponsors': sponsors.map((e) => e.toJson()).toList(),
    'total': total,
  };
}

/// 单笔捐赠记录（对应 Next.js SponsorStatus.donations 数组元素）。
class DonationRecord {
  const DonationRecord({
    required this.id,
    required this.amount,
    required this.paymentType,
    required this.status,
    required this.paidAt,
    required this.createdAt,
  });

  final int id;
  final num amount;
  final String paymentType;
  final int status;
  final String? paidAt;
  final String createdAt;

  factory DonationRecord.fromJson(Map<String, Object?> json) => DonationRecord(
    id: ((json['id'] as num?) ?? 0).toInt(),
    amount: (json['amount'] as num?) ?? 0,
    paymentType: json['paymentType']?.toString() ?? '',
    status: ((json['status'] as num?) ?? 0).toInt(),
    paidAt: json['paidAt']?.toString(),
    createdAt: json['createdAt']?.toString() ?? '',
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'amount': amount,
    'paymentType': paymentType,
    'status': status,
    'paidAt': paidAt,
    'createdAt': createdAt,
  };
}

/// 用户赞助状态（对应 Next.js SponsorStatus）。
class SponsorStatus {
  const SponsorStatus({
    required this.isSponsor,
    required this.sponsorSince,
    required this.totalAmount,
    required this.donationCount,
    required this.sponsorRank,
    required this.donations,
  });

  final bool isSponsor;
  final String? sponsorSince;
  final num totalAmount;
  final int donationCount;
  final int? sponsorRank;
  final List<DonationRecord> donations;

  factory SponsorStatus.fromJson(Map<String, Object?> json) => SponsorStatus(
    isSponsor: json['isSponsor'] == true,
    sponsorSince: json['sponsorSince']?.toString(),
    totalAmount: (json['totalAmount'] as num?) ?? 0,
    donationCount: ((json['donationCount'] as num?) ?? 0).toInt(),
    sponsorRank: (json['sponsorRank'] as num?)?.toInt(),
    donations:
        (json['donations'] as List?)
            ?.whereType<Map>()
            .map((e) => DonationRecord.fromJson(Map<String, Object?>.from(e)))
            .toList() ??
        const [],
  );

  Map<String, Object?> toJson() => {
    'isSponsor': isSponsor,
    'sponsorSince': sponsorSince,
    'totalAmount': totalAmount,
    'donationCount': donationCount,
    'sponsorRank': sponsorRank,
    'donations': donations.map((e) => e.toJson()).toList(),
  };
}

/// 创建赞助记录参数（对应 Next.js createDonationRecord 的 params）。
class CreateDonationRecordParams {
  const CreateDonationRecordParams({
    this.userId,
    required this.outTradeNo,
    required this.amount,
    required this.paymentType,
  });

  final int? userId;
  final String outTradeNo;
  final num amount;
  final String paymentType;

  Map<String, Object?> toJson() {
    final map = <String, Object?>{
      'outTradeNo': outTradeNo,
      'amount': amount,
      'paymentType': paymentType,
    };
    if (userId != null) map['userId'] = userId;
    return map;
  }
}

/// 创建支付订单参数（对应 Next.js createPayOrder 的 params）。
class CreatePayOrderParams {
  const CreatePayOrderParams({
    required this.type,
    required this.name,
    required this.money,
    required this.clientip,
    required this.outTradeNo,
    this.method,
    this.device,
  });

  final String type;
  final String name;
  final String money;
  final String clientip;
  final String outTradeNo;
  final String? method;
  final String? device;

  Map<String, Object?> toJson() => {
    'type': type,
    'name': name,
    'money': money,
    'clientip': clientip,
    'out_trade_no': outTradeNo,
    'method': method ?? 'web',
    'device': device ?? 'pc',
  };
}

/// 统一响应包装（对应 Next.js getSponsorList / getSponsorStatus 的返回类型）。
class SponsorResponse<T> {
  const SponsorResponse({required this.code, this.data, this.message});

  final int code;
  final T? data;
  final String? message;
}
