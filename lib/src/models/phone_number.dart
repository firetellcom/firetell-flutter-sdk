/// Represents a phone number (DID) accessible by an agent or team.
class PhoneNumber {
  const PhoneNumber({
    required this.id,
    required this.number,
    this.title,
    this.countryCode,
    this.dialCode,
    this.status = 'active',
    this.capabilities,
    this.enableOutbound = true,
    this.sharedTeamsId,
    this.createdAt,
  });

  factory PhoneNumber.fromJson(Map<String, dynamic> json) {
    return PhoneNumber(
      id: json['id'] as String? ?? '',
      number: json['number'] as String? ?? '',
      title: json['title'] as String?,
      countryCode: json['country_code'] as String?,
      dialCode: json['dial_code'] as String?,
      status: json['status'] as String? ?? 'active',
      capabilities: json['capabilities'] is Map
          ? PhoneNumberCapabilities.fromJson(
              json['capabilities'] as Map<String, dynamic>,
            )
          : null,
      enableOutbound: json['enable_outbound'] as bool? ?? true,
      sharedTeamsId: (json['shared_teams_id'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  /// Unique phone number ID.
  final String id;

  /// Phone number in E.164 or national format.
  final String number;

  /// Display name or label (e.g. 'Support US', 'Sales Hotline').
  final String? title;

  /// ISO 3166-1 alpha-2 country code (e.g. 'US', 'VN').
  final String? countryCode;

  /// Country calling code (e.g. '1', '84').
  final String? dialCode;

  /// Status of the phone number ('active', 'inactive', etc.).
  final String status;

  /// Supported capabilities (voice, sms).
  final PhoneNumberCapabilities? capabilities;

  /// Whether this phone number can be used as an outbound caller ID.
  final bool enableOutbound;

  /// Teams that have access to this phone number.
  final List<String>? sharedTeamsId;

  /// Created timestamp.
  final DateTime? createdAt;

  /// Formatted display label (e.g. "+14155552671 (Support US)").
  String get displayLabel {
    if (title != null && title!.isNotEmpty) {
      return '$number ($title)';
    }
    return number;
  }

  @override
  String toString() => 'PhoneNumber(id: $id, number: $number, title: $title)';
}

/// Phone number capabilities.
class PhoneNumberCapabilities {
  const PhoneNumberCapabilities({
    this.voice = true,
    this.sms = false,
  });

  factory PhoneNumberCapabilities.fromJson(Map<String, dynamic> json) {
    return PhoneNumberCapabilities(
      voice: json['voice'] as bool? ?? true,
      sms: json['sms'] as bool? ?? false,
    );
  }

  final bool voice;
  final bool sms;
}

/// Paginated response for phone numbers.
class PhoneNumbersResponse {
  const PhoneNumbersResponse({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory PhoneNumbersResponse.fromJson(Map<String, dynamic> json) {
    final rawList = json['data'] as List<dynamic>? ?? [];
    final meta = json['meta'] as Map<String, dynamic>? ?? {};

    return PhoneNumbersResponse(
      data: rawList
          .whereType<Map<String, dynamic>>()
          .map(PhoneNumber.fromJson)
          .toList(),
      total: (meta['total'] as num?)?.toInt() ?? rawList.length,
      page: (meta['page'] as num?)?.toInt() ?? 1,
      limit: (meta['limit'] as num?)?.toInt() ?? 20,
      totalPages: (meta['total_pages'] as num?)?.toInt() ?? 1,
    );
  }

  final List<PhoneNumber> data;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
}
